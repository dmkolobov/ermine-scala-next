# Stage 4 DRAFT — typechecking performance and interactivity

DRAFT, written 2026-09-10 for the user to read before it is folded into
`tracker/LSP-ROADMAP.md`.  Nothing here is committed and no code was run to
produce it: it is planning built on the Stage-3 reports, PERF-ROADMAP, and the
prior-art survey `tracker/loopmodel/STAGE4-PRIOR-ART.md` (cited by section as
[survey §x] throughout).  Format follows the Stage-2 and Stage-3 sections of the
roadmap: GOAL, hard invariants, append-only Decisions, a checklist whose
acceptance criteria are the tick conditions, a gate written before any code, and
a STOP.

## Stage 4 — the read, and the wait (checklist, drafted 2026-09-10; G3 not yet signed off)

GOAL: make the editor round trip shorter where it is actually spent — in the
READ, not in inference — and make the one remaining interactivity cost (a
request that arrives during a check) either shorter or honestly answered, all
without touching batch semantics, without a new thread, and without an identity
scheme.  Stage 3 established the premise: inference is not the bottleneck, every
Stage-3 feature added nothing measurable, and requests already answer in
milliseconds from stored tables.  Stage 4 spends its whole budget on the parse
and on the policy around it, and it spends the FIRST item proving that the
numbers everything else is ranked against are real.

THE PERF PREMISE, with provenance.  Read every figure with its tag.

- MEASURED (`tracker/tools/perf-bench.sh editor`, `Layout/Report.e`, 1757
  lines / 77,385 bytes, PERF-ROADMAP P1 baseline of record, commit 5d17377,
  2026-08-31): round trip **1.616 s** = read **0.770 s** + typecheck **0.515 s**
  + debounce **0.300 s** (policy, not work) + residual **0.017 s**.
- MEASURED (LSP roadmap "Gate evidence (G2)", 2026-08-31, the same file): the
  keystroke-to-diagnostics median went **2.24 s -> 1.57 s** across item 5.5;
  inference **1.03 s -> 0.45 s**; **114 of 154** components reused; the read
  (parse+rename+lower) is **0.80 s** of the 1.57 s, i.e. 64 %.  Item 6.7 has not
  run yet, so there is no G3 latency table; **6.7 re-measures this split** and
  its number, not this one, is what G4 compares against.
- MEASURED (item 6.2, 2026-09-10, interleaved A/B, `perf-bench.sh editor -k 15`,
  both sides under load 1.3, report `tracker/loopmodel/LSP3-6.2-LOCALS.md` §6):
  pooled BEFORE **1.6635 s** vs AFTER **1.6500 s**, Δ **−13.5 ms**; the fix
  round **1.631 -> 1.610 s**, Δ **−21 ms**.  Both inside the 5 % / 80 ms budget
  and below the harness's noise floor.  The read segment wandered **0.795-0.865 s**
  between runs of an unchanged tree — that spread is the machine, and it is
  larger than most things this stage could win by tuning.
- MEASURED (item 6.5, 2026-09-10, server-side median of 10 on Report.e line
  1504): completion **2.5 ms** for prefix `f`, **1.8 ms** empty, **5.3 ms** cold /
  **0.2 ms** cached for module context; the unfiltered payload once, **1,332
  items / 181 KB / 34 ms**.  Requests are not the problem.
- ARITHMETIC (survey §0.1, from PERF-ROADMAP P2's 1970-sample editor profile;
  the middle column of that table is the survey author's arithmetic on sample
  shares): parse ≈ **0.70 s** — 91.4 % of the read; extent scan ≈ 0.054 s (since
  cut 11.5x by P5(a)); lower ≈ 9 ms; rename ≈ 2 ms; reassoc ≈ 1 ms.  Rename +
  reassoc + lower together are **1.1 % of samples ≈ 12 ms**.
- THE WARNING THAT GOVERNS ALL OF THE ABOVE ARITHMETIC.  PERF-ROADMAP: "READ
  EVERY PERCENTAGE IN THIS SECTION AS AN UPPER BOUND."  P5(a) measured one
  directly and JFR had over-attributed it **3.5x** (profile 4.7 % ≈ 66 ms;
  direct microbenchmark of the identical pass **18.80 ms**, then 1.64 ms after
  the fix; 50 reps after 20 warm-ups).  Item **7.0 is the direct measurement
  that replaces the arithmetic**, and no later item may be judged against a
  profile share.
- MEASURED, WITH A DISCLOSED DEVIATION (survey §4.3): a standalone Java
  microbenchmark — NOT the Ermine build, not sbt, not `bin/ermine` — put the
  full-sync `didChange` frame at 79,538 bytes, its parse with this project's own
  scanner at ~369 µs, an incremental frame at ~2 µs, and the string splice at
  6-16 µs, against a ~1,300,000 µs check.  That is 0.03 % of one check.  The
  survey flags it as indicative and asks for `perf-bench.sh` before anything is
  decided on it; Decision (d) below decides only to do nothing, which needs no
  re-measurement.
- CODE-DERIVED, NOT YET MEASURED (survey §5(b-lite), reading
  `TolerantCheck.keys`): each group's key contains the statement's START LINE, so
  **inserting one line at the top of the file changes every key and reuse falls
  to 0 of 154**, paying the whole ~0.5 s of inference for an edit that changed
  nothing.  Item 7.2 measures the cliff before it fixes it.
- MEASURED (roadmap Stage-3 invariant; the check cost is the wait): a request
  arriving during a check waits for it, worst case ≈ **1.3 s** on Report.e.  6.7
  records the figure of record.

## STAGE-4 INVARIANTS (hard)

Carried from Stage 3 unchanged:

- BATCH SEMANTICS ARE FROZEN.  `Session.load`/`loadModule`, `NewPipeline.readModule`,
  `SurfaceParsers.module` and the REPL goldens (`tracker/repl-tests/*.expected`,
  `TestReplDifferential`) stay byte-identical.  Every new entry point lives BESIDE
  a strict one, never as a flag inside it.  `TestTolerantRead`'s 180-file
  agreement property is the standing tripwire.
- NO REQUEST TRIGGERS WORK.  hover/definition/references/rename/symbols/
  completion/codeAction keep answering from the last check's stored tables.
  Staleness is documented, never papered over with an inline check.
- Decision 5 stays: the resident session is interface-free (`useInterface=false`).
- Single-threaded dispatch stays (Decision 3) — see Decision (c) below, which
  makes that a Stage-4 position rather than an inherited default.
- Every sweep covers stdlib AND `core/examples` (the 180-file rule; 253 files
  through `Resident.checkFile` in the 6.2-era sweeps).
- lsp-smoke's check count GROWS with each item (454 as of 6.6); the Baselines
  note is updated in the same commit.
- GATES per `tracker/GATE-POLICY.md`.  Tier 0 before every commit.  **Tier 1 for
  any change inside `scalaparsers` (the parser library — `ParseState`, `Parser`,
  the `Free` interpreter), `Subst.scala` or `Type.scala`'s constraint
  construction**; an item that discovers it needs one STOPS and says so.  Tier 2
  (full `core/test`, ALONE on the tree) at adoption and once at G4.  Perf is
  measured ONLY as an interleaved A/B on an adoption item, never as a single-side
  figure, never under load.  Implementer + reviewer per item, the reviewer's
  numbers are the ones that enter the trackers, no third full run.  ONE JVM at a
  time.  Never commit red.

New, and specific to this stage:

- **NO IDENTITY IN A CACHE KEY, AND NO ID IN A CACHED VALUE THAT ESCAPES.**  The
  5.5 fingerprint cache stays keyed on text and stays alpha-invariant: a cached
  artifact may cross a run boundary only if it is CLOSED (a generalized scheme's
  own `V`s; a parsed statement's spans).  No renamer binder id and no
  Supply-minted `V` may enter a key or leave a cache entry [survey §0.2].
- **A REUSED SURFACE TREE MUST BE BYTE-FOR-BYTE WHAT A FRESH PARSE WOULD GIVE.**
  The oracle is a differential over the 180-file corpus (stdlib + examples) with
  SYNTHETIC EDIT SEQUENCES, asserting the spliced `SModule` equals a fresh
  whole-file parse **and that the diagnostics are equal** — rust-analyzer's
  `fuzz.rs` comments its diagnostics assertion out behind a FIXME [survey §1.6];
  Ermine cannot, because the diagnostics ARE the product.  Multi-edit, not
  single-edit: swift-syntax #3397 is invisible to single-edit tests [survey §1.9].
- **REUSE METADATA SURVIVES REUSE.**  Whatever guard a cached statement carries
  (the high-water mark of 7.1a) is carried FORWARD into the next cache entry, not
  merely checked once [survey §1.9, §1.12(3)].
- **NO NEW THREAD IN THIS STAGE** (Decision (c)).
- **NO NEW BUDGET FOR THE READ WITHOUT 7.0.**  Every item after 7.0 states its
  expected saving as a fraction of 7.0's DIRECTLY MEASURED phase table, and its
  gate compares against that table.

### Stage-4 Decisions (append-only; override with a note here, not silently)

- **(a) Caching SURFACE trees by statement extent needs no identity scheme, and
  is therefore not blocked by the question 5.5 parked.**  `surface/Surface.scala`
  nodes carry only an `SLoc`/`Span` and literal payloads — no node id, no binder
  id, no supply draw — and `SName`'s fixity at parse time is LEXICAL, the fixity
  environment being applied later by Reassoc.  A parsed statement therefore
  depends on nothing but its own text and its layout column: it is a closed
  value, and reusing it is the same soundness argument that already licenses the
  5.5 inference cache to splice a previous run's generalized `Type` [survey §0.2,
  §5(a)].  The identity problem bites only OPEN artifacts (lowered trees), and
  Stage 4 does not cache those.
- **(b) Stable binder / `V` identity is DEFERRED, with the number.**  Rename +
  reassoc + lower are ~12 ms (ARITHMETIC, survey §0.1); 7.0 will say what they
  really are.  Whatever a stable-id scheme is worth, it is not worth it for read
  latency.  It is also expensive to gate: `V.equals`/`hashCode` are purely the
  integer id, and id ORDER is observably load-bearing in batch — `Session.scala`'s
  own note on `-Dermine.loadInSeries` ("parallel makes draw `Supply` ids in
  thread-timing order, which reaches interface bytes through the constraint
  solver's id-hash queue"), and PERF-ROADMAP P10, where the id base alone moved
  GU05 from **743 to 47,317 draws** (MEASURED).  Any id redesign is Tier 1 plus a
  GU05 sweep at ≥ 25 bases on both sides.  If it is ever revisited, the prior art
  says do it Zinc's way — a De-Bruijn-style renumbering during the HASHING
  traversal, leaving runtime ids alone [survey §5(b)] — not an id-space redesign.
- **(c) The worker thread is DEMOTED from "the Stage-4 fork" to a parked entry
  (7.6), and `fastMode` is promoted in its place.**  A worker removes **0 ms** of
  compute from the 1.616 s round trip; its entire value is turning the ~1.3 s
  worst-case request wait into ~0 [survey §3.9, §5(d)].  Four of six surveyed
  servers bought most of that perceived latency with no thread at all (Roslyn's
  frozen-partial two-pass, VS Code's syntax-server routing, Dart's cooperative
  yielding, clangd's stale-AST reads), and Ermine's `fastMode` is already most of
  the frozen-partial design — it skips the check, keeps the read's index and
  carries the cache forward.  The three hazards a thread must answer are unchanged
  and unaddressed (`Session.depCache` is a process-global map mutated by
  `Documents.put`/`drop` mid-check; the `Supply` is shared and its draw order is
  observable; the `Documents` map is read by the sibling loader).  The survey does
  support this demotion; if the user wants the wait gone before the read is fast,
  the unpark trigger is written into 7.6.
- **(d) Incremental `didChange` is DECLINED.**  It attacks a fraction of the
  0.017 s residual; the wire/parse half is 0.03 % of one check (MEASURED with the
  disclosed deviation, survey §4.3); its supposed second benefit — handing the
  server the edit range 7.1 wants — is obtainable free by comparing statement
  texts, which `TolerantCheck.keys` already does and which Lean deliberately
  prefers over LSP edit ranges [survey §1.7, §5(e)].  Against that sits a real
  client bug class with no protocol-level detector (LSP #1706 asked for a checksum
  and was refused), and the nearest institutional precedent — Metals, same JVM,
  same lsp4j — closed the request wontfix in 2019 and is still Full in 2026
  [survey §4.2, §4.4].  Keep `change: 1`.  ONE CORRECTNESS NOTE recorded here so
  it is not lost: `Diagnostics.scala` reads `contentChanges.lastOption.text`,
  which is right for Full and silently wrong for Incremental; that line changes
  first if the capability is ever flipped.  The same measurement found `Rpc.scala`'s
  char-at-a-time string scanner costs the 369 µs and a run-based scanner measured
  ~61 µs — a ~5x win on a step that is 0.02 % of the round trip; 7.0 measures it
  in-process and it ships only if it is free (see 7.0(h)).
- **(e) The debounce becomes ADAPTIVE, but only AFTER the read is faster.**
  PERF-ROADMAP P6 already orders it last among the [E] items and says why:
  "shortening it while a check costs 1.27 s just queues more work".  It is 19 % of
  the round trip now and would be ~30 % of what remains after 7.1, which is
  exactly when it becomes worth deriving from the measured check time, clangd's
  way (`DebouncePolicy{Min=50 ms, Max=500 ms, RebuildRatio=1}`) [survey §5(f)].
  7.4 is therefore gated on 7.1 or 7.3 having landed a measured saving.
- **(f) The 6.2b pattern-binder hook keeps its place unchanged: its own Tier-1
  item, only if lambda/`case`/`do` hover is wanted, and that is the user's call.**
  Nothing in Stage 4 depends on it; it is not scheduled here.  The review's
  finding stands — the workable shape is FOUR sites on the checker's hot path
  (`instantiateType`, `unbind`, `generalize`, and the `Remember`-style eager
  substitution), behind a flag OFF in batch — and the recording-hook shape as
  first written is REFUTED (`restrictTypes` removes the recorded meta).  It stays
  in Blocked/Awaiting, listed in 7.6 with its trigger.
- **(g) 7.1 and 7.3 are ALTERNATIVES ranked by 7.0, not a sequence.**  If a
  245-byte statement parses in 0.05 ms rather than ~2.2 ms, the read stops being
  the target and the statement cache is unnecessary [survey §5(a′)].  7.0 decides
  which of them the stage builds; the loop does not start both.

### Checklist (each item ≈ one implementer + reviewer iteration; the acceptance criteria are the tick conditions)

- [ ] **7.0 DIRECT MEASUREMENT of the read's phases.**  THE ITEM EVERY LATER ITEM
  IS JUDGED AGAINST, and the one that retires the arithmetic in the premise
  above.  Instrumented timers (System.nanoTime around each phase, behind a system
  property, printed to stderr — NOT a profiler, NOT sample shares), on
  `Layout/Report.e` through `Resident.checkFile`, P5(a)'s protocol: **50 reps
  after 20 warm-up reps, medians, machine load < 1.3**.  Phases, each reported
  separately: (a) header parse; (b) `StatementExtents.scan`; (c)
  `SurfaceParsers.module` — the whole-file parse; (d) layout/vsemi work inside it
  if it can be separated without changing behaviour, else stated as
  unseparable; (e) `Renamer`; (f) `Reassoc`; (g) `Lower`; (h)
  `Definitions.index`, the env copy and the self-scrub; plus `Rpc` frame read +
  JSON parse of one full-sync `didChange` (Decision (d)).  ALSO, and this is what
  ranks 7.1 against 7.3: **one extracted 245-byte top-level statement parsed
  through `SurfaceParsers.statement` with `statementFailure`'s repositioned
  `ParseState`, same 50/20 protocol** — that single number is 7.1's per-miss cost
  AND it says how much of the whole-file parse is per-statement work versus
  per-character trampoline overhead.  Report the ratio (315 × per-statement
  time) / (whole-file parse time) explicitly.  ACCEPTANCE: a table in the item's
  report with every phase MEASURED, its rep count and its spread; each row
  compared against the survey's ARITHMETIC row with the over/under-attribution
  factor named (P5(a) found 3.5x once — find out whether the parse share is
  honest); a one-line verdict "7.1 / 7.3 / neither" with the arithmetic that
  supports it; the instrumentation ships behind a property or comes out, and the
  item says which.  No behaviour change, no default flip: Tier 0.  If (h)'s Rpc
  number reproduces the survey's 369 µs in-process, the run-based scanner is a
  ten-line optional addendum measured the same way, adopted only if it is free
  and byte-identical on the framing tests; otherwise it is dropped and said so.

- [ ] **7.1 Surface-tree cache keyed by statement extent** (conditional on 7.0's
  verdict; Decision (a) and (g)).  TWO ITERATIONS, because the first is a
  Tier-1 parser-library change and must be reviewed on its own.

  **7.1a — the high-water mark (Tier 1).**  `statement` is
  `statementAlts(bindingStatement) << atLayoutBoundary`, and `atLayoutBoundary`
  runs `StatementExtents.skipTrivia` over the text AFTER the extent, so
  byte-equality of a statement's own text is NOT sufficient for reuse — this is
  Lean's `private def` counterexample in miniature and Lezer's 0.15.0 bug exactly
  [survey §1.7, §1.3].  Five independent systems converged on the same fix and it
  is one integer: the furthest input offset the parse examined [survey §1.10].
  In a combinator parser that is a `var furthest` in `ParseState` and one `max` in
  the position-advancing primitive — which is precisely the thing Lean's note says
  "does not exist currently".  Store `examinedLength = furthest − start` per
  statement.  ACCEPTANCE: the mark is recorded and observable; the batch path is
  byte-identical (Tier 1: `looptrace-corpus.sh` + `trace-ab.py`, `ei-diff.sh
  --batch` with `-Dermine.loadInSeries=true` on both sides, `g1-validate.sh`),
  because this touches the parser library; an interleaved A/B on BOTH targets
  (batch load and editor round trip) showing the counter is free; a test that
  the mark exceeds the extent for at least one real corpus statement (an
  anti-vacuity floor — a mark that never exceeds the extent has not been shown to
  work).  USELESS ON ITS OWN: it ships only as 7.1b's precondition, or not at all.

  **7.1b — the cache (Tier 0 + Tier 2 at adoption).**  A new editor-path-only
  entry beside `NewPipeline.readModuleTolerant`; `SurfaceParsers.module` and
  `readModule` are not touched.  THE KEY: `(headWord, ordinal among extents with
  that headWord)` — rust-analyzer's `ErasedFileAstId` with its warning attached,
  the disambiguator scoped PER head word, never global — which is exactly the
  grouping `TolerantCheck.keys` already computes [survey §2.1, §5(a)].  WHAT
  INVALIDATES: an entry is reused iff (1) its extent text is byte-identical AND
  (2) no edit intersects `[start, start + examinedLength)`.  Statement merging and
  splitting need no special case: `StatementExtents.scan` recomputes every
  boundary lexically FROM THE NEW TEXT on every check and its starts are pinned
  against the parser's own splitter over 180 files, so a deleted space that fuses
  two statements shows up as a changed extent list, not as a silently reused
  stale tree — Ermine's position here is better than Lean's, which compares
  against the old command list and settles for "go up two commands" [survey §1.7].
  THE SPLICE: every top-level statement starts at column 1 and `Span` is
  `(startLine, startCol, endLine, endCol)`, so re-anchoring a reused statement is
  PURELY ADDITIVE on the two line fields — no column arithmetic, where Lezer needs
  a `cutAt` walk and a 25-character margin [survey §5(a)].  Misses are parsed from
  their own slice with `statementFailure`'s repositioned `ParseState`
  (`layoutStack = List(IndentedLayout(startCol, "statement"), IndentedLayout(1,
  "top level"))`, `bol = false`), then `SModule(fileName, header, statements)` is
  reassembled and handed to the UNCHANGED rename -> reassoc -> lower -> check
  pipeline.  KNOWN DIVERGENCE TO CLOSE: `statementFailure`'s own docstring records
  that a slice re-parse may SUCCEED where the splitter rejected (context the slice
  lacks); the differential is what decides whether that is a bug or a
  cache-miss-only path.  THE DIFFERENTIAL (the invariant above): over the 180-file
  corpus, for a generated SEQUENCE of edits per file (insert/delete a character,
  a line, a whole statement; edit at the top, the middle and the end; an edit
  that merges two statements and one that splits one), assert the spliced
  `SModule` equals a fresh whole-file parse AND the diagnostics are equal.
  EXPECTED SAVING: **0.55-0.68 s, 34-42 % of the round trip** — ARITHMETIC
  (survey §5(a)) built on the ~0.70 s parse and ~315 statements, i.e. exactly the
  figure 7.0 replaces; the item restates it against 7.0's table before it starts,
  and if 7.0's parse number is materially smaller the item does not start at all.
  BUDGET/GATE: interleaved A/B (before/after/before/after, load < 1.3) on
  Report.e; the read segment must move by at least **200 ms** pooled — anything
  smaller is inside the 0.795-0.865 s machine drift and does not justify a second
  module driver; under that, the item is REVERTED and the number recorded, the
  P5(d) precedent.  RETENTION, stated because a JVM makes it real: reference-based
  reuse makes the cache a GC root for the trees it holds; it is per open document
  and replaced wholesale per check, so it is bounded, and the item says so with a
  measured heap figure [survey §1.9].  Tier 2 at adoption (it changes shipped
  editor behaviour), plus the seven targeted suites.

- [ ] **7.2 (b-lite) Anchored positions, so the 5.5 inference cache survives an
  edit that shifts lines.**  Independent of 7.0's verdict; small; it removes a
  cliff that costs the full inference segment.  TODAY: `TolerantCheck.keys` puts
  each statement's START LINE into its group's text (`x.startLine + ":" +
  off.text(x)`), so inserting one line at the top drops reuse to **0 of 154**
  (CODE-DERIVED; the item MEASURES it first, as its before-number).  THE FIX,
  which needs no identity scheme: store positions RELATIVE to the group's start
  line, drop the start line from the key, add Δ at lookup.  `Entry.locals` is
  `Map[(Int, Int), LocalTy]` keyed by def-site, so it is one map transformation at
  read time; the `Type`s' `Loc`s only matter for notes and note-bearing components
  are never cached (the class comment says so).  This is rust-analyzer's anchored
  `Span` with its stated rationale — "storing absolute ranges will require
  recomputation on every change in a file at all times" — and Roslyn's green-node
  rule [survey §2.1, §5(b-lite)].  IT IS ALSO THE SPAN ARITHMETIC 7.1b NEEDS, so
  the two share one helper and 7.2 should land first whichever way 7.0 votes.
  ACCEPTANCE: the before/after reuse count for a one-line insertion at the top of
  Report.e (0/154 -> the number, MEASURED both sides); Decision (b) of Stage 3 —
  the drift invariant — restated and re-attacked, because it was the argument
  that put the start line in the key (the reviewer's five attacks on it are in the
  6.2 report and must be re-run against the anchored form); cache INVISIBILITY
  holds — warm == cold, byte-identical, over the 5.5 edit set extended with
  line-shifting edits; every `Loc` that ESCAPES to the client is re-anchored (the
  item enumerates them: hover, definition, references, highlight, rename edits,
  symbols, code actions) and lsp-smoke gains a fixture per escape route asserting
  a position AFTER a line-shifting `didChange`; 6.2's `locals` keys specifically
  pinned.  Tier 0 + the seven targeted suites; Tier 2 at adoption.

- [ ] **7.3 The parse constant factor — P5(c) reopened AS AN INVESTIGATION, with
  a kill criterion.**  P5(c) named the target and stopped: the `Free` trampoline
  is 52.6 % of editor samples and `Parser.run` alone 23.2 % (ARITHMETIC, P2's
  profile), and P5(d) TRIED a localized fix and reverted it at 43 ms, below the
  ~50 ms floor, with the finding that matters: most parsing is SEQUENCING inside
  grammar rules rather than repetition, so `many`/`some` are a small share of
  total binds and **no localized combinator fix can reach that cost — P5(c) is
  architectural or nothing** (MEASURED, interleaved B,A,B,A, 1.611 -> 1.568 s
  pooled; read 0.800 -> 0.788 s).  THE NEW EVIDENCE the survey brings [§1.11] is
  a system with the SAME profile signature — allocation inside combinator
  plumbing — where inlining the combinators gave **3.65x**, removing the combinator
  layer **48.2x** and a C++->C port **52.8x** (`tree-sitter-haskell`, third-party
  report, not measured here).  SCOPE: an INVESTIGATION producing evidence, not a
  rewrite.  Deliverable: (i) 7.0's per-statement number decomposed — how much of
  it is grammar work versus `Free` interpretation, measured by a targeted
  microbenchmark of one hot grammar rule with and without the trampoline on a
  SCRATCH copy in an isolated worktree; (ii) a written estimate of what a
  de-trampolined `Parser` would cost to build and to gate (it is the parser
  library: Tier 1, the 180-file differential, byte-exact REPL goldens, and it is
  the same object `bin/ermine`'s batch load runs through); (iii) a recommendation.
  KILL CRITERION, written before the work starts: if the prototype's measured
  improvement on ONE hot rule projects to less than **300 ms** of the Report.e
  read, or if it cannot be shown byte-identical on the 180-file differential, the
  item is CLOSED with the number and P5(c) is marked "measured, not worth it" —
  no third attempt without new evidence, the P5(d) rule.  NO PRODUCTION CODE in
  this item; nothing merged; the worktree is deleted.  Tier 0 on the main tree
  (which is untouched).

- [ ] **7.4 Adaptive debounce, derived from the measured check time** (Decision
  (e); gated on 7.1b or 7.3 having landed a measured saving — if neither did, this
  item is skipped and the reason recorded).  Replace the fixed 300 ms with
  clangd's shape: `debounce = clamp(Min, RebuildRatio × measured_check_time, Max)`
  over a rolling median of the last N checks, `Resident` already logging the
  number on every check.  Starting constants to be argued in the item from 7.0's
  and 7.1b's tables, not copied: clangd ships `{50 ms, 500 ms, ratio 1}` [survey
  §5(f)].  ACCEPTANCE: the round-trip median on Report.e AND on a small file
  (both MEASURED, interleaved A/B), because the whole point is that a small file
  stops waiting 300 ms for nothing; a pinned test that a burst of N keystrokes
  produces exactly one check; no oscillation — the policy is stated as a function
  and the item shows its output at the measured check times of the fast and slow
  file; the number, the rule and the reason are written into docs/lsp.md.
  Tier 0; Tier 2 at adoption (it changes shipped behaviour).

- [ ] **7.5 Ticket triage — which of E5-E10 this stage takes.**  One iteration,
  and it takes only the ones that are editor-path Tier 0.  DISPOSITIONS:
  - **E8 (parser columns tab-expanded to 8-column stops)** — **TAKE**.  Every
    editor range on a tab-indented line is 7 columns right of the text per tab
    (6 of 71,248 corpus occurrences, `core/examples/GridExample.e`).  User-facing
    and small: the boundary conversion in one helper every range goes through,
    editor path only, Tier 0.  NOT the `Pos` fix, which is Tier 2 + goldens.
  - **E9 (stdlib navigation lands in the BUILD OUTPUT)** — **TAKE**.  A user who
    edits the file `workspace/symbol` lands in loses the edit at the next
    `copyResources`.  Rewrite the target tree back to
    `core/src/main/resources/modules` at the LSP boundary
    (`Definitions.location`), editor path only, Tier 0 — and the pins must become
    tree-distinguishing, since every current pin is `uri.endswith("/Bool.e")`-shaped
    and cannot see the bug.
  - **E7 (import-failure suppression covers term names only)** — **TAKE IF CHEAP,
    otherwise state and defer**.  Operators cost three read diagnostics per use
    and type names one note, all cascading from one failed import.  Editor path,
    Tier 0, but the ticket says the hard part is POLICY not plumbing (the same
    three diagnostics are right for a genuinely mistyped operator), so the item
    ships a flag-based tag or writes down why it cannot be stated.
  - **E5 (`loadModulesInSeries` vs `loadModules` on already-loaded modules)** —
    **NOT THIS STAGE**: a one-line loader change, but shipped loader behaviour, so
    Tier 2 + Tier 1's `ei-diff.sh` sweep in series + `g1-validate.sh`.  It rides
    along with the next Tier-2 commit that is due anyway; the item notes which.
  - **E6 (lambda blame at the application)** — **NOT THIS STAGE**: a checking-mode
    rule for `Lam` moves the position and sometimes the wording of every such
    refusal — REPL goldens, two `TestStage1Pins` anchor pins and the corpus verdict
    TEXT all re-cut.  Tier 2 + goldens, its own item, and frozen batch semantics
    forbid it here.
  - **E10 (`Pretty` writes four type shapes the grammar cannot read back)** —
    **SPLIT**: (5), the quick fix's blindness to the file's own type synonyms
    (33 refusals), is editor path and Tier 0 — TAKE if 7.5 has room.  (1)-(3), the
    printer proper (48 groups), change published `.ei` bytes because the same
    printer writes interfaces: Tier 1 with the interface sweep and a re-cut
    `g1-baseline`.  NOT THIS STAGE.
  ACCEPTANCE: each taken ticket closed with its own lsp-smoke fixture (count
  grows); each deferred one has its disposition and tier written back into
  `tracker/TICKET-stdlib-findings.md` in the same commit, so the ticket file and
  the roadmap agree.

- [ ] **7.6 PARKED, with triggers** (no work in this stage; listed so the forks
  do not go missing).
  - **The 6.2b pattern-binder `Subst` hook** (Decision (f)).  TRIGGER: the user
    says lambda/`case`/`do` hover is wanted.  Then it is its own Tier-1 item in
    the workable four-site shape, behind a flag OFF in batch, with a perf line for
    the flag check on the BATCH target, sized as a day with review.  Until then
    the 62.4 % equation-argument coverage stands.
  - **Checks on a worker thread** (Decision (c)).  TRIGGER: 6.7's measured
    worst-case request wait is still over ~500 ms AFTER 7.1b or 7.3 has landed —
    i.e. the cheap moves failed to make the wait tolerable.  The cheaper thing to
    try FIRST, and the thing to try before any thread: promote `fastMode` to the
    first pass of every check with the accurate pass enqueued behind it, which
    publishes navigation and syntax diagnostics without new concurrency [survey
    §5(d)].  If a thread is nonetheless built, it must answer `depCache`, the
    `Supply` (give the worker `Supply.split`, never share the block allocator) and
    the `Documents` map, per the parked fork and survey §3.9.
  - **A proper incremental parser** — parked permanently unless the front end is
    replaced for other reasons.  See "What this stage does NOT do".

**GATE G4** (written before any code, per the roadmap's format):

- GREEN: Tier 0 on every commit (`core/compile core/copyResources`, `TestLoopTrace`
  720/720, `corpus-run.sh --batch` verdicts unchanged at 85/69/0 over 154,
  `repl-smoke.sh` 8 groups, `lsp-smoke.sh` at its new grown count); the seven
  targeted suites on any item touching TolerantCheck/Lower/Renamer/Definitions;
  **Tier 1 for 7.1a and for anything else that reaches into `scalaparsers`**
  (`looptrace-corpus.sh` + `trace-ab.py`, `ei-diff.sh --batch` in series on both
  sides classified with `ei-classify.py`, `g1-validate.sh`); **Tier 2 = full
  `core/test` ALONE on the tree**, green, once at the gate and at each adoption
  commit; REPL goldens and `TestReplDifferential` BYTE-UNCHANGED;
  `TestTolerantRead`'s 180-file agreement property green; boot 129 modules; no
  `.ei` droppings in `tracker/lsp-tests`.
- NUMBERS RECORDED: (1) **7.0's directly measured phase table**, before and after
  the stage, with the over/under-attribution factor against the survey's
  arithmetic named for each row; (2) an **interleaved A/B** (before/after/before/
  after, both sides under load 1.3) for EVERY adoption item — 7.1b, 7.2, 7.4 —
  with the pooled Δ and an explicit statement of whether it clears the ~50 ms
  editor noise floor and the 0.795-0.865 s read drift; (3) the **corpus
  differential** for 7.1b: 180 files × the synthetic multi-edit sequence, spliced
  parse == fresh parse AND diagnostics equal, with the edit-sequence generator
  and its seed recorded; (4) the reuse counts for 7.2 (0/154 -> N on a top-of-file
  line insertion); (5) the worst-case request wait, re-measured, next to 6.7's
  figure; (6) a heap figure for 7.1b's retention; (7) every REVERTED item with the
  number that killed it (the P5(d) precedent — a measured negative is a result).
- The G3 gate must be signed off and 6.7's re-measured latency table must exist
  before 7.1b or 7.4 is judged; 7.0 may run before it, and should.
- **STOP the loop and summarize for sign-off before any Stage 5 planning.**

### What this stage does NOT do

- It does not build an incremental parser.  matklad, who implemented block
  re-parse in rust-analyzer: "In practice, incremental reparsing doesn't actually
  matter much for IDE use-cases" — and it is still not enabled.  Lezer sets a
  ~1 KB floor below which it does not reuse; Ermine's mean top-level statement is
  ~245 bytes, four times BELOW that floor.  Wagner & Graham's canonical paper has
  no measured speedup and its author puts layout-sensitive languages outside the
  model; tree-sitter's answer for Haskell layout is 3,471 lines of hand-written C
  [survey §1.1-1.3, §1.6, §5(c)].  Sub-statement granularity also has nothing to
  invalidate: 5.6 established that a `where`-block is never a binding component of
  its own.
- It does not switch `textDocumentSync` to Incremental (Decision (d)).
- It does not add a thread, and it does not change Decision 3 (Decision (c)).
- It does not build a stable binder / `V` identity scheme (Decision (b)), and it
  does not cache LOWERED trees — only surface trees, which carry no identity.
- It does not touch `Subst.scala` or `Type.scala`.  6.2b stays parked (Decision (f)).
- It does not change batch semantics, the strict reader, the REPL goldens or the
  `.ei` printer.  E6 and E10(1)-(3) are named and deferred for exactly that reason.
- It does not add hover on arbitrary sub-expressions.  Inference does not annotate
  the tree; that is a typed-tree design and it belongs with whatever follows 6.2b.
- It does not shorten the debounce before the check is shorter (Decision (e)).
- It does not re-rank anything on a profiler share.  After 7.0, shares are for
  deciding where to look, never for deciding what was won.
