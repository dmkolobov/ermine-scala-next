# Ermine performance roadmap — loop state file

This file is the durable state for the /loop driving the performance work.
Each iteration: read this file, do the next unchecked item, verify every
baseline, commit with an iteration-log entry appended here and the checkbox
ticked.  A design fork not settled under "Decisions" goes under
"Blocked/Awaiting" and STOPS the loop.  Background and the original profile:
tracker/TICKET-perf-type-inference.md.  Editor-path measurements and the
machinery they came from: tracker/LSP-ROADMAP.md, Stage 2 (item 5.5 and the
G2 gate evidence).

Status: P1, P2 and P5(a) DONE (2026-08-31).  G3-0 signed off.  The harness
exists, the BASELINE OF RECORD is measured, both targets are freshly profiled,
and the first optimization has landed — with the loop's most useful finding so
far being that the profile over-attributes a tight loop 3.5x, so every share
quoted here is an upper bound.  NEITHER TARGET HAS MOVED MEASURABLY YET.
NEXT: P3 (free-variable collection, on the batch target — the one whose ~1%
noise floor can verify a modest win).

## The two targets

The ticket knows about one of these.  Stage 2 of the LSP work produced the
other, and it does not obey the ticket's headline finding.  EVERY checklist
item declares which target it serves, and what its ceiling is on the other.

**[B] BATCH LOAD** — loading the 129 stdlib modules with full inference.
MEASURED AT HEAD: **11.46s** interface-free, **5.59s** with the `.ei` cache
(medians of 5 fresh-JVM reps each, spread 0.11s and 0.17s; see Baselines for
the full line).  The inherited estimates were ~12s and ~6s, so they held.  The
profile was RE-TAKEN AT HEAD by P2 (4209 samples, 1ms sampling,
`tracker/tools/jfr-buckets.py`), and it does not agree with the ticket:

| phase                       | ticket 2026-08-30 | HEAD (P2) |
|-----------------------------|-------------------|-----------|
| type/kind inference         | 79.0%             | **55.4%** |
| parsing                     | 18.7%             | **33.3%** |
| session driver / IO         |  2.2%             |  3.8%     |
| rename / reassoc / lower    | —                 |  1.4%     |
| term evaluation             | ~0.1%             | ~0%       |

Leaf families — what an optimization would actually attack:

| family                                            | ticket   | HEAD (P2) |
|---------------------------------------------------|----------|-----------|
| free-variable collection (`.vars`, `Vars.apply`)   | ~40%     | **33.0%** |
| substitution application (`.sub`, `.subst`)        | 10-15%   | **20.9%** |
| parser trampoline (`scalaparsers.*` via `Free`)    | —        | **27.3%** |
| parser failure merging (`Fail.++`)                 | —        |  3.2%     |

**READ EVERY PERCENTAGE IN THIS SECTION AS AN UPPER BOUND.**  P5(a) measured
one of them directly and JFR had over-attributed it **3.5x**: the profile put
`StatementExtents.offsetOf` at 4.7% of the editor round trip (~66ms), and a
direct microbenchmark of the identical pass put it at 18.8ms.  Tight loops with
a safepoint poll at the back edge are sample magnets.  Before investing in any
item below on the strength of its share, MEASURE THE PASS DIRECTLY — the share
tells you where to look, not what you will get.

So the ticket's headline is roughly a third too high, parsing is roughly
twice what it claimed, and **substitution is now nearly two thirds the size of
free-variable collection rather than a quarter of it** — P4 and P3 are closer
in value than the ticket implies.  Also corrected: the ticket's "963 of 967
samples sit on one `ermine-session-task` thread" is thread-NAME aggregation.
By thread ID the busiest thread holds **72.3%**, with 27.7% spread over 20+
others, so the loader is genuinely parallel — and Amdahl therefore caps a
perfect parallelization of the batch target at about **1.4x** (see P8).

**[E] EDITOR ROUND TRIP** — keystroke to `publishDiagnostics` on
Layout/Report.e (1757 lines), through the resident LSP session.  MEASURED AT
HEAD by the harness (median of rounds 2..15, round 1 discarded as JIT
warm-up); the LSP 5.5 column is the inherited ad-hoc number:

| segment                     | before 5.5 | after 5.5 | HARNESS @HEAD | share |
|-----------------------------|------------|-----------|---------------|-------|
| read (parse/rename/lower)   | 0.89s      | 0.80s     | **0.770s**    | 48%   |
| typecheck (inference)       | 1.03s      | 0.45s     | **0.515s**    | 32%   |
| debounce (policy, not work) | 0.30s      | 0.30s     | **0.300s**    | 19%   |
| residual (env copy, scrub…) | —          | —         | **0.017s**    |  1%   |
| **median round trip**       | **2.24s**  | **1.57s** | **1.616s**    | —     |

NOT DIRECTLY COMPARABLE to 5.5's 1.57s, and the reason is worth carrying:
the harness's pinned edit invalidates more than 5.5's did — **97 of 154**
components reused where 5.5 got 114 of 154 — so it does more inference per
round on purpose.  From here on the harness number is the baseline; 5.5's is
history.

**"Inference dominates" is FALSE on this path.**  Of the 1.302s of actual
compute, parse+rename+lower is **59%** and inference **40%**, with the whole
rest of the round trip — session env copy, the nine-pass self-scrub, header
parse, extent scan, `Definitions.index`, protocol write — measuring 0.017s,
which closes the question of whether the `check:` line was hiding anything.
A perfect fix to the [B] hotspot (free-variable collection, ~40% of batch
samples) therefore has a hard ceiling on [E] of about a tenth of the round
trip.  Items aimed at [E] must aim at the read path or at the debounce, not at
inference, unless a profile says otherwise.

P2 TOOK THAT PROFILE (1970 samples, all on `main` — single-threaded, as
Decision 8 requires), and it is sharper than the timing split:

| phase        | share | | leaf family              | share |
|--------------|-------|-|--------------------------|-------|
| parse        | 62.7% | | parser trampoline        | 52.6% |
| inference    | 30.8% | | free-variable collection | 14.8% |
| extent scan  |  4.8% | | parser failure merging    |  8.3% |
| lower        |  0.8% | | substitution application |  8.9% |
| rename       |  0.2% | | extent scan              |  4.8% |
| reassoc      |  0.1% | | grammar (ermine parsers) |  0.9% |

**THE READ IS THE PARSER, and nothing else.**  Rename, reassoc and lower
together are **1.1%** — P5 named them as suspects and the profile clears them.
61% of the whole editor round trip is inside `scalaparsers`: the `Free`
trampoline every combinator runs through, plus `Fail.++`.  The three named
targets, in profile order, are in P5.

## Baselines (hard invariants — never commit red)

Toolchain:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    # node (for the VS Code extension test only): ~/.local/node/bin

Green before EVERY commit:

- `sbt -batch core/test` — 902 total, 901 pass.  The ONLY allowed failure is
  `Constraints.disjunction sound` (known pre-existing, tracker/06-tests.md).
  Suites GROW; a commit that adds tests updates the count in its log line.
- `bash tracker/tools/repl-smoke.sh` — 4 suites PASS (aliasing 2, relations 6,
  scoping 4, smoke 23).  smoke runs with `useInterface=false`, so it also
  guards inference behaviour.
- `bash tracker/tools/lsp-smoke.sh` — 82 checks PASS.
- `printf ':quit\n' | bin/ermine` — "Loaded 129 modules".
- `(cd editor/vscode && npm test)` — extension load + grammar tests.
- KNOWN FLAKE: core/test suites run concurrently in one JVM and rarely
  interfere.  A red that is not the known Constraints failure gets ONE re-run
  before diagnosis; if it reproduces, it is real — do not commit.  New flakes
  get root causes, not retries-forever (LSP-ROADMAP's log has worked examples).

### BASELINE OF RECORD (P1, 2026-08-31, commit 5d17377 + the harness itself)

Machine: dmitry-Z370P-D3, 12 cores, 15.6GB, JDK 21.0.12.1+1, default max heap
3984MB, 1-minute load average below 1.0 at every start.  Reproduce with
`tracker/tools/perf-bench.sh both -n 5 -k 15` and
`tracker/tools/perf-bench.sh batch --warm -n 5`.

| target                          | median  | min   | max   | reps |
|---------------------------------|---------|-------|-------|------|
| [B] batch cold (interface-free) | 11.46s  | 11.41 | 11.52 | 5    |
| [B] batch warm (`.ei` cache)    |  5.59s  |  5.57 |  5.74 | 5    |
| [E] editor round trip           |  1.616s | 1.548 | 1.754 | 14   |
| [E] editor read                 |  0.770s | —     | —     | 14   |
| [E] editor typecheck            |  0.515s | —     | —     | 14   |
| [E] LSP boot (interface-free)   | 11.90s  | —     | —     | 1    |
| [E] first check after didOpen   |  1.993s | —     | —     | 1    |

The [B] figures are the ones the program computes for ITSELF ("Loaded 129
modules (X.XX seconds)"); process wall time was 12.27s cold and 6.42s warm and
is NOT comparable across commits, because it also folds in JVM startup, the
logo and `Lib.preamble`.  The [E] figures are a client-side monotonic clock for
the round trip and the server's own `%.2f` split for read/typecheck.

WHAT IS COMPARABLE ACROSS COMMITS, and what is not — quote accordingly:
- COMPARABLE: the [B] in-process medians on this machine at this heap and this
  `.ei` state; the [E] read/typecheck pair; and `reused A of B`, which is a
  pure counting statistic and load-independent.
- NOT COMPARABLE: any wall-clock figure; anything across machines (the
  classpath file holds absolute paths and the heap is RAM-derived); cold
  against warm; editor round 1 against rounds 2..K; and any run whose
  `reused/components` ratio differs from its comparison run.

The ticket's own "Baselines to hold" section is STALE (it says 753 props; it is
902) and is superseded by this section.

## Correctness oracles (inference changes are silent; the suite alone will not catch them)

- **`.ei` ALPHA-EQUALITY over all 129 modules is the authority.**
  `tracker/tools/g1-validate.sh` (+ `g1-normalize.py`, `g1-diff.sh`).
  1447/1447 alpha-equal was the G1 result.  Run it for ANY change to
  Subst.scala, Type.scala, Kind.scala, Vars.scala or the solver.
- **REPL goldens** (`tracker/repl-tests/*.expected`) stay BYTE-unchanged.
- **TestTolerantRead's 180-file sweep** asserts the editor checker is silent on
  everything the batch loader accepts — it catches an optimization that changes
  what type-checks.
- **KNOWN TRAP**: `lookbackJoin`'s residual constraint set in Relation.ei is
  solver-order sensitive — it is why `-Dermine.loadInSeries` exists.  Any change
  to solve order or to constraint-set ITERATION ORDER will move interface bytes.
  That is not automatically wrong, but it is a GATE QUESTION (Decision 9), never
  something to wave through.
- Every corpus sweep covers `core/src/main/resources/modules` AND
  `core/examples` — 180 files.  Never the stdlib alone.

## Decisions (pre-made; overridable with a note here, not silently)

1. **NO OPTIMIZATION WITHOUT A PROFILE POINTING AT IT.**  If the cost cannot be
   shown in a profile or a harness timing, it may not be "optimized".
2. **`tracker/tools/perf-bench.sh` is the measurement of record.**  Ad-hoc
   timings are not evidence.  Every commit records BEFORE and AFTER from the
   same harness on the same machine, with the repetition count, in its log
   entry.  A commit that cannot show a number does not claim a speedup.
3. **Say which you are quoting.**  Sample PROPORTIONS are robust to background
   load; wall time is not.  Wall-time claims state the machine was quiet and
   give a median over N, not a single run.
4. **A change that does not measurably help is REVERTED**, and the negative
   result is written into the iteration log.  Negative results are the most
   valuable output of this loop — they stop the next session retrying them.
   AMENDED 2026-08-31 (P5(a) forced the question): "measurably" cannot mean
   only "visible in the harness's end-to-end median", because that median has a
   NOISE FLOOR of about **50ms** on the editor round trip run-to-run (read
   wanders ±45ms across JVM instances, typecheck ±15ms, and typecheck is the
   stable one).  A change smaller than the floor may be KEPT only when a DIRECT,
   repeatable measurement of the work it removes is recorded in the log — a
   microbenchmark of the exact pass, before and after.  A change justified only
   by a profile percentage, with no direct measurement, is still reverted.  The
   harness stays the measurement of record for CLAIMS about the targets; this
   clause only governs whether a sub-floor change earns its place in the tree.
5. **Every item declares its target** ([B], [E], or both) and the ceiling it
   expects on the other.  A [B] win that does nothing for [E] is still a win;
   claiming otherwise is what this rule prevents.
6. **Correctness gate by change class.**  Touching Subst / Type / Kind / Vars /
   the solver => g1-validate 1447/1447 + REPL goldens byte-unchanged + all five
   baselines.  Editor-path only => all five baselines (TestTolerantRead's sweep
   is inside core/test).
7. **Batch semantics are FROZEN** (inherited from LSP Stage-2's hard invariant).
   `Session.load` / `loadModule` / the REPL keep strict refusals byte-for-byte.
8. **The LSP resident session stays single-threaded (LSP decision 3) and
   interface-free (LSP decision 5).**  Turning interfaces back on is not an
   available optimization: a stale `.ei` lets type errors through and sends
   definition targets into interface text.
9. **Interface-byte movement stops the loop.**  If a change makes g1-validate
   report anything other than 1447/1447 alpha-equal — including the known
   solver-order sensitivity — it goes to Blocked/Awaiting for sign-off with the
   diff summarized, not into a commit.
10. **`SessionEnv` is not thread-safe, by its own scaladoc.**  Parallel module
    loading (ticket candidate 4) is a DESIGN item with its own scope deliverable
    before any code — 963 of 967 samples on one thread is a symptom, not an
    invitation.
11. **`*.ei` files are gitignored build products and measurement
    contamination.**  Never commit them; delete or bypass them before any
    inference measurement (loads write them back, so a "cold" second run is not
    cold).
12. **Several sources are CRLF** — edit byte-wise, never with line-oriented
    tools that normalize endings.

## Checklist

Ordering rationale: the harness before any measurement, fresh profiles before
any change, then the cheapest change with the largest profiled share, then the
[E] read path, then the two big design items last.

- [x] **P1 [B+E] The harness — `tracker/tools/perf-bench.sh`.**  Everything
  after this measures with it.  Requirements:
  (a) **batch mode**: N repetitions of an interface-free load of the 129 modules
  (`-Dermine.useInterface=false`, `.ei` cleared first and asserted absent
  after), each in a FRESH JVM — cold JIT is what a batch user actually pays;
  report per-rep, median, min, and spread.  Also a warm/`.ei` mode for the
  ~6s number, clearly labeled as a different measurement.
  (b) **editor mode**: boot the resident LSP once, then K rounds of
  didChange-to-publishDiagnostics on Layout/Report.e, measuring client-observed
  round trip AND harvesting the server's own `check: … read Xs, typecheck Ys
  (reused A of B components)` line (Resident.scala:222).  Edits must change a
  fingerprint — the 5.5 log records that appending trailing whitespace changes
  none, because an extent ends just past its last significant character, and
  that flattered the first measurement.  Warm-JVM, in-process, single boot:
  that IS the editor's steady state.  Probably a `perf-client.py` beside
  lsp-client.py rather than a mode inside it — the smoke client's job is
  assertions, not timing.
  (c) a **machine-readable summary line** on stdout, e.g.
  `PERFBENCH commit=<sha> host=<h> reps=<n> batch_cold_median_s=… batch_warm_median_s=… editor_median_s=… editor_read_s=… editor_check_s=… reused=A/B loadavg=…`
  (d) print the machine's load average with the results, and refuse (or loudly
  warn) if it is high — Decision 3 depends on it.
  (e) assert no `.ei` droppings are left behind.
  DELIVERABLE: the script, plus its first full run recorded in the log as the
  BASELINE OF RECORD, superseding every number in this file's target tables.

- [x] **P2 [B+E] Fresh profiles for both targets.**  No code changes; this item
  produces evidence only.
  (a) Re-take the batch JFR at HEAD with the ticket's recipe (`stackdepth=512`,
  `jfr print --stack-depth 500`; the ticket's pitfalls list is load-bearing —
  `jfr print` truncates to 5 frames by default and the samples live on
  `ermine-session-task`, not `main`).  The ticket's table predates all of Stage
  1 and Stage 2; confirm or correct 79% / 40% / 10-15% before anything is built
  on them.
  (b) Take the FIRST profile of the EDITOR path — none exists.  JFR around the
  harness's K didChange rounds, bucketed to answer one question: inside the
  0.80s read, what is parse/layout, what is Renamer, what is Reassoc, what is
  Lower/TyLower, and what is the tolerant splitter's re-parsing?
  DELIVERABLE: two tables of sample proportions in the log, and a named top-3
  leaf list per target.  The next item chosen is whichever P3-P7 those tables
  point at; if they point somewhere not listed here, add an item.

- [ ] **P3 [B, ceiling ~15% on E] Free-variable collection** (ticket candidates
  1 and 5) — **33.0% of batch samples, 14.8% of editor samples** (P2 measured;
  the ticket's ~40% was high).  Confirmed as the single largest leaf family on
  the batch target.  In order,
  each measured separately, each reverted if flat:
  (a) **Representation** — `Vars` threads an immutable `Set[V[J]]` through every
  traversal (Vars.scala) and `++`/`--` rebuild it; a mutable seen-set private to
  a single traversal is semantically invisible (the public result is the ordered
  `List` from `!`) and is the cheapest thing to try.  Watch `--`, whose current
  definition deliberately re-adds the intersection.
  (b) **Memoize per node** — types are immutable, so a cached ftv set on the
  node (or an ftv-bearing wrapper) is sound; measure allocation cost, which is
  the reason this is second not first.
  (c) Only if (a) and (b) are both flat: reconsider whether the callers are the
  problem instead — that is P4.
  GATE: Decision 6 applies (g1-validate + goldens).  Variable ORDER is
  observable — `Vars` promises order of appearance and `.ei` text depends on it.
  A representation that reorders is a Decision 9 stop, not a commit.

- [ ] **P4 [B] Redundant `vars`/`sub` calls in the solver** (ticket candidate
  2).  P2 RAISED THIS ITEM'S VALUE: substitution application is **20.9%** of
  batch samples, not the 10-15% the ticket estimated, which puts it within
  reach of P3 rather than far behind it.  Instrument first — a counter around `typeVars`/`sub` keyed by call site,
  run the 129-module load, and print the top call sites by count.  A guess about
  which of `subsumeType` / `instantiateType` / `inferBindingGroupTypes`
  recomputes the ftvs of the same type is not evidence; the counter is.  Then
  eliminate only the recomputation the counter proves is redundant within one
  binding group.  GATE: Decision 6.

- [ ] **P5 [E] The editor read path — SCOPED BY P2's PROFILE.**  The read is
  the parser: rename+reassoc+lower are 1.1% of samples and are OUT of scope.
  Three named targets, cheapest first, each measured separately and reverted
  if flat:
  (a) **DONE 2026-08-31 — `StatementExtents.offsetOf`, and the profile was
  3.5x wrong about it.**  Fixed (one line-start index per `keys` call): the
  pass goes **18.80ms -> 1.64ms** on Layout/Report.e, 11.5x, directly measured
  over 50 reps after 20 warm-up reps.  That is 17ms of a 1.6s round trip —
  **1.1%, under the harness's ~50ms noise floor**, so the end-to-end median did
  NOT move and the profile's 4.7% (~66ms) was an over-attribution.  Kept under
  the amended Decision 4, on the direct measurement.  The original reasoning,
  which was right about the defect and wrong about its size:  It walks
  the file from offset 0 counting lines and columns on EVERY call
  (StatementExtents.scala:85-98), and `text` calls it TWICE per extent
  (:100-102).  Report.e has ~315 top-level statements, so one check does ~630
  full walks of a 77KB string — and `TolerantCheck.keys` calls `text` for
  every group and every scope item on every keystroke.  Fix: scan once into a
  line-start index, or compute all offsets in the single pass the scanner
  already makes.  Isolated, no semantic surface, and the corpus sweep in
  TestStatementExtents is the oracle.
  (b) **`Fail.++` — 8.3%, and it is the same immutable-set pathology as the
  ftv one.**  Every recoverable parse failure merges `expected: Set[String]`
  with `m.expected ++ expected` (ParseResult.scala:56-62), and the tolerant
  splitter's per-statement `.attempt` makes failures the common case, not the
  exception.  The merged set is only ever rendered into an error message, so
  a lazier representation (a list, or a thunk that unions on demand) is
  semantically free — but the rendering must stay byte-identical, which the
  REPL goldens and lsp-smoke's position fixtures pin.
  (c) **The `Free` trampoline — 52.6%, and it is architectural.**  Every
  combinator in `scalaparsers` runs through `scalaz.Free`
  (`Parser.run` alone is 23.2% of the editor round trip).  This is a big
  change and probably its own design item; do NOT start it before (a) and (b)
  report.
  STILL TRUE AND STILL RESPECTED: parse+rename+lower runs WHOLE every check by
  design — LSP 5.5's review established that renamer binder ids and Lower's
  supply-minted Vs are FRESH EVERY RUN, so cached LOWERED trees cannot be mixed
  with a fresh run.  Incremental didChange (sync kind 2) remains available and
  cheap, but the profile says it would only shrink the 0.9% grammar slice and
  whatever re-reading costs — not the trampoline.  Split across commits; each
  one green.

- [ ] **P6 [E] The 300ms debounce, once compute drops below it.**  19% of the
  round trip today and pure policy.  When P3-P5 have moved compute, re-derive
  the debounce from the measured check cost instead of leaving it at the number
  5.3 picked.  Cheap, but LAST among the [E] items: shortening it while a check
  costs 1.27s just queues more work.

- [ ] **P7 [B] Substitution representation** (ticket candidate 3) — PROMOTED
  2026-08-31 ahead of P3 on the `instantiateType` evidence.  **DESIGN WRITTEN,
  see "P7 DESIGN" below.**  Original framing kept for the record:
  write the design into this file (what replaces `HasTypeVars.sub`'s whole-tree
  rebuild, what happens to `Subst`'s existing structure, how `.ei` output stays
  byte-identical) and take it to Blocked/Awaiting for sign-off BEFORE writing
  code.  Do not start this before P3 and P4 have reported — they may take enough
  of the 10-15% that this stops being worth its risk.

- [ ] **P8 [B] Parallel module loading** (ticket candidate 4) — DESIGN ONLY
  until scoped, per Decision 10.  P2 ALREADY MOVED THIS ITEM'S PREMISE TWICE,
  in opposite directions.  The ticket said the load is effectively serial (963
  of 967 samples on one thread); that was thread-NAME aggregation, and by
  thread ID the busiest thread holds **72.3%** with 27.7% spread over 20+
  others — so the loader is ALREADY parallel and the item is not "add
  concurrency" but "widen it".  The same number caps the prize: 72.3% on the
  critical thread bounds a perfect parallelization at about **1.4x**, which is
  worth knowing before anyone touches a `SessionEnv` that its own scaladoc says
  is not thread-safe.  First deliverable is still cheap and still worth taking:
  **measure the actual width of the 129-module dependency DAG by level** and
  compare it against that 72.3%.  Only if the width is real does the second
  deliverable follow: a written scope of exactly which `SessionEnv` state is
  shared and mutated during a load, and what would have to change.  No
  concurrency code lands from this item without its own gate.

- [ ] **P9 [E, unblocks a feature] Per-binding inference cost.**  Hover on local
  binders in the LSP is pinned to null SOLELY because inference is too slow to
  run per-hover (LSP-ROADMAP decision; Definitions.scala).  After P3/P4, measure
  what inferring ONE binding costs.  If it fits a hover budget (say <100ms on
  Report.e's largest definition), say so in the log with the number — that turns
  a gated feature into an available one and is a hand-off to the LSP roadmap,
  not work done here.


## P7 DESIGN (written 2026-08-31; awaiting sign-off before any code)

### The measured problem

`instantiateType` (Subst.scala:182-188) rewrites the ENTIRE substitution map on
every variable instantiation, and maps `remembered` too.  The class comment
above `SubstEnv` states why (Subst.scala:87-92): *"We maintain the invariant
that all the types/kinds in the map are always fully substituted, so we never
need to further substitute something that we look up."*  It is a deliberate
design decision, not an oversight, and everything below is about what depends
on it.

Measured: `instantiateType` is the nearest enclosing driver for **42% of
ftv/substitution samples on a record/chart-heavy example and 44% on the stdlib
batch**, `subsumeType` second at 27%/33%.  A SECOND quadratic sits beside it —
`instantiateKind` (Subst.scala:176) also rewrites the whole TYPE map, and is
reached from inside every `unifyType` variable case via `kindCheck`
(Subst.scala:236).  It is NOT inside the 42-44% figure; `kindCheck` completes
before `instantiateType` is entered.

### Step 0 — THE GATE (done; it was the blocking prerequisite)

Decision 6 makes `g1-validate.sh` mandatory for exactly this change class, and
**it had not worked since post-G1 D3.**  Four breakages, all now fixed:
`run old` (retired in 80df1eb, exits 2); `tools.G1Importing` (deleted in
9ad5909, ClassNotFoundException); an assertion of exactly 5 group parse-errors
(it is 3 — Stage 1's split pipeline re-parses two modules the fused one could
not, so the gate reported an IMPROVEMENT as a failure); and
`tracker/g1-baseline`, committed at G1 as a drift tripwire and referenced by
nothing in tracker/tools, never once checked.
It failed loudly (exit 1) rather than passing silently, so nobody was misled —
it simply had not been run since D3.
**Re-established at HEAD: double run, 129 files, 1447 signatures, EQUIVALENT.**

**GATE QUESTION FOR SIGN-OFF — re-record `tracker/g1-baseline`?**  On its first
arming the tripwire reported 1447 signatures with exactly ONE differing:
`lookbackJoin`, the documented solver-order-sensitive residual.  1446/1447 are
alpha-identical to the G1 baseline; browse/groups differ because Stage 1
replaced the pipeline.  So the baseline is STALE, not the tree drifted.  It is
left ADVISORY rather than re-recorded, because re-recording a golden is a
Decision 9 act.  Re-record it and the tripwire becomes a real gate for P7; do
not, and P7 has only the double-run self-agreement, which proves determinism
but not stability against the pre-P7 tree.

### Step 1 — two representation-neutral wins, FIRST

Neither touches the invariant and neither can move a `.ei` byte; both are
measurable on [B], whose noise floor is ~1%.  Do these before any
representation change, so P7's own number is measured against a clean floor.
  (a) `Kind.subKind` (Kind.scala:90) has NO empty-map fast path, unlike
  `Type.subType` (Type.scala:606-607 `case m if m.isEmpty => a`).  And
  `AppT.subst`/`AppT.map` (Type.scala:213, :209) allocate a fresh node even
  when both children are unchanged.  Adding the guard and a physical-equality
  short-circuit makes the CURRENT eager rewrite cheaper and produces `eq`
  trees.  One stated side effect: more node sharing means
  `AppT.memoizedKindSchema` (Type.scala:214) survives rewrites more often —
  only closed schemas are cached (Subst.scala:495), so it should be safe, but
  it is a behaviour change to kind-inference caching, not a pure allocation
  win, and the commit must say so.
  (b) `Vars.contains` (Vars.scala:37) is `exists(_ == v)`, and `Vars` overrides
  only `foreach`, so `exists` goes through `ForeachIterable.iterator`
  (ForeachIterable.scala:17-21), which materialises the WHOLE variable Vector
  with no early exit.  That is paid by every occurs check (Type.scala:667,
  reached from Subst.scala:203/206/235/238 — every unification variable case)
  and by `ts partition (tvs contains _)` at Subst.scala:1089.  `Vars.scala:36`
  carries the author's own warning about exactly this.

### Step 2 — instrument BEFORE choosing a representation

Three counts, each cheap, each decisive.  No design survives without them:
  **ALL THREE ANSWERED 2026-08-31 — see the iteration log.  Headline:
  `reopened = 0`, so retaining bindings is NOT ruled out; `instantiateKind`
  is a real but secondary 12.8%; and the M^2 term is a BATCH problem, because
  per-SCC envs make the editor's mean M 46x smaller.**
  (i) **Does `restrictTypes` ever re-open the boundness guard?**
  `hm.types.get(v)` (Subst.scala:182) is the ONLY guard against double
  instantiation, and `restrictTypes` DELETES keys (Subst.scala:153), so after a
  restrict a second `instantiateType` on the same variable legally succeeds and
  binds it to something different.  Any scheme that RETAINS bindings so chains
  can be chased turns that into the panic at Subst.scala:183.  Count it over
  the 129 modules.  **If it ever fires, mutable cells are off the table in
  their simple form.**
  (ii) **`instantiateKind` (line 176) vs `instantiateType` (line 186)** — how
  many whole-map rewrites each, and how many bytes each rebuilds.  Most kinds
  are `Star` and fall through `case _ if (e1 == e2)` at Subst.scala:211, so
  `instantiateKind` may fire rarely; nothing currently knows.
  (iii) **How large does `hm.types` actually get** on the per-module env
  (Session.scala:858) versus the editor's per-SCC envs (TolerantCheck.scala:246
  already creates a fresh SubstEnv per component)?  M is the term in M^2.

### Step 3 — the representation, conditional on Step 2

NOT "mutable metavariables with levels".  Levels are refused for now: nothing
in the tree LOWERS levels on binding, `Gamma` demonstrably contains live
metavariables (Subst.scala:781, :874, :958), and `generalize` runs at App and
Lam nodes rather than let-nodes — so a level predicate would silently
over-generalize.  Levels need their own measurement showing where
"free in Gamma" and the level test disagree on the corpus.

The candidate is **lazy resolution with value write-back**:
stop the eager sweep at Subst.scala:186, resolve on read, and WRITE THE
RESOLVED VALUE BACK into the map so the invariant is re-established lazily and
the cost amortises.  Write-back — not union-find path compression — is what
stops the quadratic reappearing: the dominant cost is resolving STRUCTURE, not
walking variable chains.  Two things this requires that a naive version misses:
the read must RECURSIVELY resolve what it returns (`VarT.subst`, Type.scala:225,
returns the looked-up value verbatim and never re-descends), and every site that
MATCHES on type shape must walk first — `unifyType`, `matchFunType`,
`occursCheckType` (Type.scala:665-667, whose `case VarT(_) => false` is sound
only because a residual VarT is known unbound), and the predicate machinery
`pnf`/`isPNF` (Subst.scala:330-331).

`restrictTypes` must be SPLIT, not removed: keep every binding for RESOLUTION,
and give restrict a second, smaller LIVE KEY SET which is what the escape scans
iterate (Subst.scala:286, :543 via :100-101).  Making it a no-op instead would
reject currently-accepted programs at Subst.scala:537-543 AND change ftv(Gamma)
at :793-794, hence which variables generalize, hence the inferred scheme.

### Named silent-divergence sites — the ones that change a TYPE, not crash

Every one of these must be argued individually in the implementing commit:
Subst.scala:793-794 (restrict-then-`substGamma`, changes ftv(Gamma) hence
generalization); :182 (the boundness guard re-opening); :537-543 (subsumption
escape scan — `tts` are e2's LEGITIMATE instantiations and deleting them is
what stops them reading as escapes); :286 (masked skolem escape — must
zonk-through-masked-keys THEN mask); constraint discharge (`entails` compares
with raw `==` at :314, `pnf` treats any residual VarT as head-normal at :330,
`Ambiguity.simple` at :360 — an unwalked bound VarT makes a discharged
constraint look undischarged, adding a residual constraint, which DOES trip the
.ei oracle at G1Compare.scala:74); the structural fallbacks `case _ if
(e1 == e2)` at :269 and :211 (Forall and Exists have no `equals` override, so
that branch is REFERENCE equality); and `substAlias` at :220-221 with
`unifyType`'s AppT case recursing on an unsubstituted head at :242.

### Verification, beyond the existing oracles

The suite mostly catches crashes; these changes produce wrong TYPES.  So:
the repaired `g1-validate.sh` double run; the baseline tripwire once
re-recorded; REPL goldens byte-unchanged; and a differential the tree does not
have yet — **dump the fully-resolved type at every `generalize` (Subst.scala:1114)
over the 180-file corpus and diff before/after.**  That is the only instrument
that sees a changed inferred type that still renders alpha-equal.

**GATE G3**: stop the loop for sign-off when either target has moved enough to
be worth reviewing, or when the remaining candidates all need design decisions.
Summarize: numbers before and after (from the harness, with reps), what was
tried and REVERTED, and what the profile says the next bottleneck is.

## Blocked / Awaiting

**(empty — G3-0 signed off 2026-08-31, user: "Keep going".)**

**GATE G3-0 — SIGNED OFF 2026-08-31.**  Iteration 1 turned the ticket plus the
Stage-2 editor measurements into the checklist above and stopped for sign-off;
the answer was to proceed, so the ordering below stands as written and P1 ran.
Kept here because both points still govern later items:

1. **Item ordering puts [B] work (P3, P4) before the [E] read path (P5)**, on
   the grounds that the batch profile is the one that exists and P2 will confirm
   it cheaply.  If the editor round trip is the priority, P5 should move ahead
   of P3 and P2(b) becomes the first profile taken.
2. **P7 (substitution representation) and P8 (parallel loading) are design items
   that will come back here for their own sign-off** rather than being attempted
   inside a normal iteration.

**ORDERING, RE-OPENED BY P2's OWN EVIDENCE AND SETTLED HERE (2026-08-31) —
recorded rather than done silently, and overridable with a note.**  G3-0 signed
off an ordering that puts [B] work (P3, P4) ahead of the [E] read path (P5), on
the stated grounds that the batch profile was the one that existed.  P2 removed
that grounds: both profiles now exist, and the editor one found a QUADRATIC —
`StatementExtents.offsetOf` re-walks the file from offset 0 on every call, ~630
times per keystroke.  P2's own clause in this checklist says "the next item
chosen is whichever P3-P7 those tables point at", and the tables point at
P5(a) first.  ORDER FROM HERE, as of P2: P5(a), then P5(b), then P3.

**REVISED AGAIN AFTER P5(a) — and it lands back on what G3-0 signed off.**
P5(a) measured the two targets' NOISE FLOORS, which nobody had:

| target             | run-to-run spread | as % of the target | smallest visible win |
|--------------------|-------------------|--------------------|----------------------|
| [B] batch cold     | 0.11s on 11.46s   | ~1%                | ~0.15s               |
| [E] editor total   | ~0.05s on 1.62s   | ~3%                | ~0.05s               |
| [E] editor read    | ±0.045s on 0.82s  | ~5.5%              | ~0.05s               |

[B] resolves 1%; [E] cannot see anything under ~50ms, and after the 3.5x
over-attribution correction most remaining [E] candidates are plausibly in that
range — P5(a) certainly was, at 17ms.  So the editor path can only be moved by
something big (P5(c), the trampoline, which is architectural and needs its own
design), while the batch path can VERIFY a modest win.  **NEXT IS P3**, which
is the biggest single leaf family (33.0%, upper bound) on the target that can
actually measure it — which is the ordering G3-0 signed off in the first place,
now with evidence rather than convenience behind it.  P5(b) stays queued: worth
doing, but microbenchmark `Fail.++` FIRST, because if it is another sub-floor
17ms it should be judged as one.

Known forks that will land in this section when reached: P7's design; P8's scope
if the DAG has real width; the `Free`-trampoline question inside P5(c), which is
52.6% of the editor round trip and almost certainly its own design item; and the
stable-binder-identity scheme that deeper [E] reuse would need (named and
deferred by LSP 5.5).

## Iteration log

- 2026-08-31 (P0 — seeded).  Created this file from
  tracker/TICKET-perf-type-inference.md (read in full: JFR profile, five
  candidate directions, repro recipe, pitfalls) and tracker/LSP-ROADMAP.md's
  Stage-2 entries (5.5 and the G2 gate evidence — the only editor-path
  measurements that exist).  NO CODE TOUCHED, no measurement taken; the five
  baselines were not re-run because the diff is one new tracker document and
  cannot affect them — P1 re-baselines everything, including the test counts,
  which the ticket had at 753 props against today's 902.
  THE SUBSTANTIVE FINDING RECORDED HERE: the ticket describes one target and
  the loop has two.  The ticket's "79% inference" is a BATCH number; on the
  editor round trip, after LSP 5.5's per-SCC reuse, inference is 35% of compute
  and parse+rename+lower is 63%.  Every checklist item is therefore labeled with
  the target it serves, and P2 must take an editor-path profile — none has ever
  been taken.  Loop stopped for G3-0.

- 2026-08-31 (P1 — the harness, and the first numbers of record).
  `tracker/tools/perf-bench.sh` + `tracker/tools/perf-client.py`.  Both targets,
  a machine-readable `PERFBENCH` line, per-rep artifacts under `$PERF_OUT`, and
  a `PERF_JVM_PROPS` hook so P2 can hang JFR flags off the harness instead of
  hand-rolling a command line and quietly ceasing to be the measurement of
  record.  BASELINE OF RECORD is in the Baselines section; the headline figures
  are [B] cold **11.46s**, [B] warm **5.59s** (medians of 5 fresh-JVM reps,
  spreads 0.11s and 0.17s) and [E] **1.616s** (median of rounds 2..15, spread
  0.206s).  The inherited estimates — ~12s, ~6s, 1.57s — all held.

  WHAT THE HARNESS HAD TO DEFEND AGAINST, because each of these produces a
  plausible-looking wrong number rather than an error:
  `ermine.useInterface` DEFAULTS TO TRUE while `ermine.typeCheck` DEFAULTS TO
  FALSE (SessionState.scala:98-100), so the natural command line measures a
  warm load of untyped modules; a cold rep under the default writes all 129
  `.ei` back and contaminates every rep after it (which is why cold runs pass
  `useInterface=false`, and the run asserts 0 `.ei` afterwards).  The "Loaded
  … modules" text does NOT start a line — the progress bar emits `\r` frames
  with no newline — and `ordinal()` spells small counts as WORDS, so a rep is
  validated on the captured count being exactly 129 and never on the exit code,
  which is 0 even after a panic (Console.scala:815-827).  Decimal separators
  come from the default FORMAT locale on BOTH sides, so both JVMs are pinned to
  en_US, the shell to LC_ALL=C, and every capture accepts `[0-9.,]`.  And the
  `.ei` delete is scoped to the module tree: `find . -name '*.ei' -delete` from
  the repo root would destroy 143 TRACKED files — the whole G1 golden baseline
  and the comparator fixtures — so the script cross-checks that it and
  g1-diff.sh agree on the directory before deleting anything.

  THE EDIT IS THE EXPERIMENT, and it is pinned and asserted (perf-client.py):
  one digit of an integer literal inside `emptyReport`'s body, Report.e:281.
  It satisfies all four constraints the reuse machinery imposes — changes a
  fingerprint (interior, not trailing: an extent ends just past its last
  significant character, which is why the 5.5 measurement was invalidated by a
  whitespace edit), moves no scope key, changes no line count, lands in a named
  definition — and `emptyReport` is referenced 14 times elsewhere in the file,
  so the invalidation is a real transitive closure rather than one leaf.  It
  invalidates MORE than 5.5's edit did: **97 of 154** components reused where
  5.5 got 114 of 154.  So 1.616s is not comparable to 5.5's 1.57s, and the
  Baselines section says which figures are comparable across commits at all.

  ONE PREMISE CONFIRMED, ONE SHARPENED.  Confirmed: on the editor path
  parse+rename+lower is **59%** of compute and inference **40%** — the roadmap
  said 63/35 from 5.5's lighter edit, and the direction is what matters.
  Sharpened: the residual — everything the server's `check:` line does not
  cover but the round trip pays, i.e. the env copy, the nine-pass self-scrub,
  the header parse, the extent scan, `Definitions.index` and the protocol
  write — measures **0.017s**, 1% of the round trip.  That closes a real
  question (the survey flagged the gap as "not obviously small") and means P5
  can aim at the read path without hunting for hidden overhead first.

  TWO BUGS IN MY OWN HARNESS, both caught by its output rather than by review,
  and both worth recording because they are the shape of measurement error:
  (1) the stale-build guard cried stale on a current tree — sbt's resource copy
  PRESERVES the source mtime but truncates it to milliseconds, so a fresh copy
  reads microseconds OLDER than its source; fixed with 2s of slack.  (2) The
  first editor run reported a NEGATIVE residual for the didOpen round, because
  I subtracted the 300ms debounce from a check that does not pay it — didOpen
  checks immediately.  The steady-state numbers were unaffected, but the editor
  half was re-measured after the fix so the recorded baseline comes from the
  committed code.  Same discipline for the batch half: after a late shell-side
  locale pin the script was re-run and reproduces — 11.33s over 3 reps against
  the recorded 11.46s over 5, 1.1% apart, inside run-to-run variation.
  Also verified as a positive control: an editor run leaves the 129 `.ei`
  untouched, which is the interface-free invariant (Decision 8) holding in
  practice and not just in the Resident's constructor.

  NO OPTIMIZATION WAS ATTEMPTED and none may be until P2 reports.
  Baselines: core/test 902 total, 901 pass, 1 fail (`Constraints.disjunction
  sound`, the known one); repl-smoke 4 suites; lsp-smoke 82 checks; boot 129
  (5.78s warm); `npm test` PASS.  No Scala was touched — the diff is two new
  tracker/tools scripts and this file.

- 2026-08-31 (P2 — fresh profiles, and the ticket does not survive them).
  Both recordings taken THROUGH the harness's `PERF_JVM_PROPS` hook, which is
  what that hook was for: `tracker/tools/jfr-buckets.py` is the new analysis
  tool, and it prints thread, phase and leaf-family tables from a `.jfr`.
  Phase attribution uses the INNERMOST matching frame, because the phases nest
  — attributing to the outermost would file every batch sample under "session",
  since `Console.main` is at the bottom of every stack.  Shared utilities
  (Type, Kind, Vars) are deliberately not phase rules; they belong in the leaf
  table, not stealing samples from whichever phase drove them.
  No code was changed and nothing was optimized.

  [B] BATCH, 4209 samples at 1ms (a 472-sample run at the default 10ms agrees
  within 3.5 points on every bucket, so this is not small-sample noise):
  inference **55.4%**, parse **33.3%**, session 3.8%, rename/reassoc/lower
  1.4%.  THE TICKET SAID 79.0% / 18.7%.  Leaf families: free-variable
  collection **33.0%** (ticket: ~40%), substitution application **20.9%**
  (ticket: 10-15%), parser trampoline **27.3%** (ticket: not identified).
  So the headline is a third too high, parsing is twice what was claimed, and
  substitution is close enough to ftv collection that P4 is no longer the
  poor relation of P3.

  [E] EDITOR, 1970 samples, 100% on `main` — Decision 8's single-threading
  holding in practice.  parse **62.7%**, inference **30.8%**, extent scan 4.8%,
  and rename+reassoc+lower **1.1% between them**.  P5 named rename and lower as
  suspects; the profile clears them and names three real targets instead, now
  written into the item: `StatementExtents.offsetOf` (4.7%, quadratic — it
  walks from offset 0 on every call and `text` calls it twice per extent, so
  one keystroke does ~630 full walks of a 77KB string), `Fail.++` (8.3%,
  merging immutable `Set[String]` expected-sets on every recoverable failure,
  which the tolerant splitter's per-statement `.attempt` makes the common
  case), and the `scalaz.Free` trampoline every combinator runs through
  (52.6%, architectural, explicitly not to be started before the other two
  report).  The first two are the same pathology the ticket found in `Vars`
  — rebuilding immutable collections in a hot loop — in a place the ticket
  never looked.

  A CORRECTION THAT CUTS BOTH WAYS.  The ticket's "963 of 967 samples sit on a
  single ermine-session-task thread" is thread-NAME aggregation: by thread ID
  the busiest holds 72.3% and 27.7% is spread over 20+ others.  So the loader
  is not serial, P8 is not "add concurrency" but "widen it" — and the same
  number caps the prize at about 1.4x, which is the cheapest thing anyone has
  learned about P8 so far.

  ONE BUG IN THE NEW TOOL, caught because the first family table disagreed
  with the leaf table it was summarising: `Vars\$\$anon` matches
  `HasTypeVars$$anon$6.sub` as a SUBSTRING, so substitution samples were being
  filed as free-variable collection and ftv read 44.6% instead of 33.0%.  The
  rule now anchors on the package dot and the file says why.
  Baselines unchanged from P1 (no Scala touched): core/test 902/901+known,
  repl-smoke 4, lsp-smoke 82, boot 129, npm test PASS.
  NEXT: P3, or P5(a) — see the note under Blocked/Awaiting.

- 2026-08-31 (P5(a) — the quadratic is real, the profile's number was not).
  `StatementExtents.Offsets`: one line-start index per source string, so a run
  of position lookups costs one pass plus a per-line walk instead of a walk
  from offset 0 per lookup.  The per-line walk STAYS, because a column is not
  an offset — tabs advance to the next multiple of 8 — and it is
  character-for-character the tail of the original loop, so it keeps the
  original's behaviour in the corner that matters: when `col` overshoots its
  line the newline IS consumed and the answer lands just past it.  An index
  that clamped to the line end instead would have shifted every fingerprint
  `TolerantCheck.keys` computes, silently.  `keys` now builds one index and
  uses it for all ~1182 lookups (591 extents x 2) instead of 1182 full walks
  of a 77KB string.

  THE NUMBER, AND WHY IT IS NOT AN END-TO-END NUMBER.  Direct measurement of
  the identical pass, 50 reps after 20 warm-up reps: **18.80ms -> 1.64ms**,
  11.5x.  The harness's editor median did NOT move (1.616s before, 1.674s
  after; typecheck 0.515s before, 0.515s after) because 17ms is 1.1% of the
  round trip and the run-to-run noise floor is about 50ms — read alone wanders
  ±45ms between JVM instances.  So this is a KEPT change under an amended
  Decision 4, not a claimed speedup: the roadmap now distinguishes a sub-floor
  change with a direct repeatable measurement (may be kept, measurement
  recorded) from one justified only by a profile share (still reverted).

  THE FINDING THAT MATTERS MORE THAN THE FIX.  The P2 profile put this loop at
  4.7% of the editor round trip, which is ~66ms; it is 18.8ms.  **JFR
  over-attributed it 3.5x.**  A re-profile after the fix confirms the work
  really is gone — extent scan 4.8% -> 0.1%, `offsetOf` off the leaf table
  entirely — while the wall clock stayed put, which is exactly the signature of
  sample bias rather than of a fix that did not work.  Tight loops with a
  safepoint poll at the back edge are sample magnets.  Every remaining share in
  this roadmap is therefore an UPPER BOUND: P5(b)'s 8.3%, P5(c)'s 52.6% and
  P3's 33.0% say where to look, not what they will pay.  The two-targets
  section now says so at the top, and the next item to touch any of them must
  microbenchmark the pass before investing in it.

  THE ORACLE.  TestStatementExtents +2 (4): the pre-P5(a) walk is written out
  as a naive reference, and the indexed version must agree with it at every
  probed position over all 180 corpus files — including the degenerate columns
  (-1, 0) and the overshoot (len+1, len+9) — 1.06M probes; and every extent's
  `text` must be byte-identical, 12k extents.  Both proved.
  NOT TOUCHED: SurfaceParsers has its own private `offsetOf` with the same
  shape (SurfaceParsers.scala:872), used only by the 5.2 statement-failure
  re-parse.  It drew ZERO samples in either profile — broken statements are
  rare — so no profile points at it and it stays as it is.
  Baselines: core/test **904** total (901+known was 902; +2 are this item's own
  properties), 903 pass, 1 fail (`Constraints.disjunction sound`, the known
  one); repl-smoke 4 suites; lsp-smoke 82 checks; boot 129; npm test PASS.
  NEXT: P3 — see the revised ordering note in Blocked/Awaiting; P5(a)'s
  noise-floor numbers put the measurable prize back on the batch target.

- 2026-08-31 (ROW-CONSTRAINT SOLVING — investigated on a user's recollection
  that it was historically one of the slowest parts of Ermine.  NEGATIVE
  RESULT for perf, and a REAL ROBUSTNESS FINDING.  No code changed.)
  The recollection is corroborated by an unmerged upstream commit: **04c2308,
  Dan Doel, 2018-08-27, "Bail out of row constraint solving if it takes too
  long"**, on branch `features/limit-row-solving`, verified NOT an ancestor of
  HEAD.  It adds a 50,000-step countdown to `incorporateAll` and an exception
  named **`Eternity`**, and on catching it returns the constraint set unsolved.
  So the historical fear was RUNAWAY SATURATION / NON-TERMINATION, not
  steady-state slowness.  `Constraints.scala` has been touched five times ever
  and never optimized.

  MEASURED, and it does not reproduce here.  Constraint solving is now its own
  phase in jfr-buckets.py (it was folded into `inference`, which is why it was
  invisible): **0.4%** of samples on Layout/Report.e, **0.4%** on
  Relation/Op.e — the densest row module in the repo at 0.32 constraints/line,
  10x Report.e — and **1.2%** of the batch load.  A dedicated editor run on
  Relation/Op.e typechecks in 20ms with 6 components.

  WHY IT IS QUIET, WHICH IS NOT "THE BENCHMARK MISSES IT".  The heavy row
  modules are all INSIDE the boot closure (Relation.e and Layout/Report.e rank
  1 and 2 of all 161; everything outside the closure is lighter), so there is
  nothing heavier to load.  The residual sets the solver actually produces are
  tiny: of 1474 signatures in the 129-module interface tree, 105 of 129 modules
  produce ZERO partition constraints, 126 constrained signatures carry exactly
  one, and **the global maximum is 15** (`lookbackJoin`, Relation.e:206).  An
  all-pairs saturation over n<=15 cannot be hot.  There is also a STRUCTURAL
  reason it stays small: row constraints are legal only in strictly positive
  positions (Subst.scala:862, Type.scala:201), so they cannot accumulate across
  a higher-order boundary.

  THE ALGORITHM IS STILL THE SHAPE YOU WOULD WORRY ABOUT.  `incorporateAll`
  (Constraints.scala:743) is forward-chaining saturation with an all-pairs
  comparison per worklist step (`learnPartitions`, :805), and FOUR rules mint
  FRESH variables that re-enter the queue (splitConcrete :795, resolution
  :1021, commonSubexpression :1076, disjunction :1105) with NO step budget.
  The cubic rule is one uncomment away: `disjunction`'s call sites at :814-818
  and :823-831 are commented out, making it dead code in production.  The
  file's own header predicts this at :208-212 ("one would probably expect an
  algorithm using the rules above to not perform very well").

  THE ACTIONABLE PART IS NOT PERF.  An unbounded saturation loop inside the
  resident LSP is a HANG risk: the server is single-threaded by decision, so a
  pathological input does not slow the editor down, it stops answering
  forever.  Batch at least dies with a REPL prompt still alive.  Upstream
  already wrote the fix and never merged it.  This belongs to the LSP roadmap's
  robustness debt, not here — flagged, not scheduled.
  ALSO WORTH KNOWING BEFORE ANYONE TOUCHES THE SOLVER: `lookbackJoin`'s
  15-constraint residual contains `r <- (r)` (vacuous) and prints
  `t <- (d, r, c)` AND `t <- (c, d, r)` — the same constraint, since RHS is a
  Set — so the saturation is non-confluent and under-trimmed, which is the
  real content of the `-Dermine.loadInSeries` trap and Decision 9.  And the
  whole-loop soundness property `incorporateAll sound` is COMMENTED OUT in
  TestConstraints.scala:483-489; only the individual rules are tested.  That
  is the missing net.

  NO ITEM IS ADDED TO THIS CHECKLIST.  Nothing in this repo can be loaded to
  reproduce the 2018 behaviour; it would have to be AUTHORED — a synthetic
  module chaining 20-50 join/rename/except calls across many distinct row
  variables, extrapolating from lookbackJoin's 6 chained calls -> 13 fresh
  existentials.  Recorded so the next session does not re-run this
  investigation from the same recollection.

- 2026-08-31 (THE ROW-CONSTRAINT CLIFF — found, bracketed and confirmed; and
  the examples corpus measured for the first time).  Follows the negative
  result above, which was right about this corpus and wrong to leave it there.

  THE CLIFF IS REAL AND IT IS AT EIGHT.  `tracker/tools/gen-row-stress.py`
  emits N left-nested `join`s in ONE UNANNOTATED definition (`join` contributes
  three partitions and three fresh existentials per call; left-nesting feeds
  each output into the next input so the RHS sets overlap without being
  identical, which is what fires `resolution` and `commonSubexpression`).  One
  JVM per N, interface-free:

  | N chained joins | solve  |          | N | solve                |
  |-----------------|--------|----------|---|----------------------|
  | 2               | 0.02s  |          | 6 | 0.79s                |
  | 3               | 0.03s  |          | 7 | **10.94s**           |
  | 4               | 0.03s  |          | 8 | **>138s, killed**    |
  | 5               | 0.13s  |          |   |                      |

  Step ratios 4.3x -> 6.1x -> 13.8x: the ratio itself grows, so this is worse
  than exponential, which is what an unbounded worklist that MINTS NEW WORK
  looks like.  A JFR profile of N=7 settles what is burning: **98.4% of samples
  in constraint solving**, split **59.7% priority-queue maintenance** (`Q.append`
  17.1%, `Q.part` 12.3%, `RHS.hashCode` 11.7%, `findRHS` 8.8%, `foldLeft` 5.2%)
  and **38.3% the rules** (`commonSubexpression` 16.3%, `cancellation` 8.6%).
  `commonSubexpression` is one of the four fresh-variable minters: it invents a
  variable, the variable re-enters the queue, the queue rebuilds and re-hashes,
  and every processed partition is compared against it again.

  WHY NOTHING IN THE REPO HITS IT — and how close it gets.  `lookbackJoin`
  (Relation.e:206), the corpus's worst real case, has SIX chained
  row-constrained calls.  The synthetic at N=6 solves in 0.79s.  **The corpus
  stops one step short of the knee.**  That is why every profile said 0.4-1.2%
  and why the 2018 `Eternity` budget (04c2308, never merged) would never have
  fired here.
  Note also `RHS.hashCode` at 11.7%: the queue key is `(rhs.hashCode,
  lhs.hashCode)` and a TypeVar's hash is its Supply-drawn id — so the SAME
  design decision produces both this cost and the residual non-determinism that
  forced `-Dermine.loadInSeries` into existence (Decision 9).

  THE EXAMPLES CORPUS, WHICH NO PROFILE IN THIS REPO HAD EVER TYPE-CHECKED.
  The boot closure is Prelude+Layout; Console appends the examples loader only
  afterwards, and every measurement in this file passed no arguments.  So the
  inferred-relational corpus was never in any of it.  Measured now, per file:
  ChartsExample 2.72s, GridExample 0.84s, PieChartLegend 0.65s, GroupBy 0.20s,
  SoftRelation 0.17s, PivotTest 0.12s, everything else <=0.09s.
  THE RELATIONAL EXAMPLES ARE THE CHEAP ONES.  PivotTest carries the most
  inferred row constraints of any example and costs 0.12s.  The expensive ones
  are the CHART/LAYOUT files, and a profile of ChartsExample says why: **82.8%
  inference, 1.7% constraint solving**, and by leaf family **35.2%
  free-variable collection + 31.6% substitution**.  That is P3 and P4 territory
  exactly, now confirmed on real user-shaped code and not just on the stdlib
  boot — which STRENGTHENS the current ordering rather than changing it.
  Incidental: four example files do not parse at all (Sample.e, Interp.e,
  Yahoo.e, guide/HelloWorld.e — e.g. `Sample.e:12:1: panic: trailing virtual
  semicolon`).  Pre-existing, unrelated, and noted so it is not rediscovered.

  WHAT THIS CHANGES.  Still NO perf item for the solver: nothing reachable in
  this repo is slow, and the fix for code that IS slow is a step budget, not an
  optimization.  What it does change is that the robustness flag now has a
  number behind it — **eight chained inferred row operations in one definition
  hangs the compiler**, and inside the single-threaded resident LSP that is an
  unrecoverable hang, not a slow save.  Porting 04c2308's budget (and reporting
  the unsolved set as a diagnostic rather than spinning) is the fix, and it
  belongs to LSP robustness debt.  A user writing a 10-way join would meet this
  on their first save.
  Reproduce: `tracker/tools/gen-row-stress.py --out /tmp/rowstress --to 8`.
  No Scala touched; the last full baseline run stands (core/test 904, repl 4,
  lsp 82, boot 129, npm PASS).

- 2026-08-31 (RECORDS ARE ROWS — a correction to the entry above, and the
  root cause of P3/P4 found).  Prompted by the observation that "record-heavy
  IS relational, records have a row type".  Correct about the type system, and
  chasing it down moved the roadmap's centre of gravity.

  RECORD ROWS ARE FREE IN ftv AND subst, which kills my implied mechanism.
  `ConcreteRho` holds `Set[Name]` — field LABELS, not type variables — so
  `typeHasTypeVars.vars` falls to `case _ => Vars()` (Type.scala:651) and never
  looks inside, and `ConcreteRho` does not override `subst`, inheriting
  `def subst(...) = this` (Type.scala:56).  **O(1) both ways.**  So the 35.2%
  ftv + 31.6% substitution in ChartsExample is NOT rows being walked.
  Row WIDTH does cost, but through a different door: `ConcreteRho.hashCode =
  fields.hashCode * 111` (Type.scala:146) is uncached and O(N), recomputed on
  every `Exists.apply` (Type.scala:277 does `p.toSet.toList`), and
  `equals` is O(N) from `unifyType`'s fallthrough.  In this corpus rows are
  never wider than 4 fields, so that term is small — but it is the term that
  would bite a wide record, and it is quadratic in width.

  WHAT ACTUALLY MAKES ChartsExample EXPENSIVE — and it does support the
  "operations on relations, when their types are inferred" framing, just not
  via literals.  Record count ANTI-correlates with cost (PivotTest: 93 record
  fields, 0.12s; PieChartLegend: 6 fields, 0.65s).  Chart-combinator
  applications correlate almost perfectly: 28 -> 2.72s, 10 -> 0.84s, 1 ->
  0.65s, 0 -> 0.12-0.20s.  And `ChartMode` (Layout/Chart.e:30-36), the type of
  `line`/`bar`/`scatter`, is a type ALIAS carrying ten universals, four class
  constraints and a **four-way ABSTRACT partition** `r <- (sr, xr, yr, o)` —
  `abstr.size >= 2`, so `splitConcrete` fires and mints fresh variables — and
  being an alias it is re-expanded at every occurrence.  So the expensive thing
  is applying wide constrained-polymorphic combinators in unannotated code.
  That is row work in inferred relational code; it just never saturates,
  because the residual sets stay small (see the cliff entry above).

  THE ROOT CAUSE, AND IT IS THE BIGGEST FINDING OF THIS LOOP SO FAR.
  `instantiateType` (Subst.scala:182-188) rewrites the ENTIRE substitution map
  on EVERY variable instantiation:

      hm.types = subType(Map(v -> e), hm.types) + (v -> e)
      hm.remembered = hm.remembered.map { case (k,(g,t,loc)) =>
        (k, (subType(Map(v -> e), g), subType(Map(v -> e), t), loc)) }

  `hm.types` is one SubstEnv per module binding group, so M instantiations cost
  O(M^2 x type size) — and each of those rewrites is exactly a `vars`/`sub`
  traversal.  Measured: `instantiateType` is the nearest enclosing driver for
  **42% of ftv/subst samples in ChartsExample and 44% in the stdlib batch**,
  with `subsumeType` second at 27%/33%.  THE SAME TWO DOMINATE BOTH WORKLOADS.
  This is the mechanism BEHIND the ticket's "40% free-variable collection,
  10-15% substitution": those are the symptom, and the whole-map rewrite is the
  cause.

  CONSEQUENCE FOR THE CHECKLIST.  P3 (cheaper ftv representation) treats the
  symptom; P4 (redundant vars/sub in instantiateType/subsumeType) and P7
  (substitution representation — mutable metavariables with levels, or
  union-find, so instantiation is O(1) instead of a map rewrite) are the SAME
  problem, and P7 is where the win is.  P7 was queued last as "big, do not
  start before P3 and P4 report".  P4 has now effectively reported, via this
  measurement, and it points at P7.  Recommend promoting P7 to a design item
  NEXT, ahead of P3.  Not doing it unilaterally: it reverses a stated ordering
  twice over and P7's own entry requires a written design and a gate.
  No Scala touched; last full baseline run stands.

- 2026-08-31 (P7 PROMOTED; DESIGN WRITTEN; AND THE GATE WAS BROKEN).
  No Scala touched.  Two deliverables: a repaired correctness gate, and the P7
  design (in full above, under "P7 DESIGN").

  THE GATE HAD NOT WORKED SINCE POST-G1 D3, which matters more than the design,
  because Decision 6 names it as mandatory for exactly this change class.  Four
  breakages: `g1-validate.sh:34` called `g1-diff.sh run old`, retired in
  80df1eb (exits 2); it ran `tools.G1Importing`, deleted in 9ad5909
  (ClassNotFoundException); `g1-diff.sh` asserted exactly 5 group parse-errors
  when it is now 3, because Stage 1's split pipeline re-parses two modules the
  fused one could not — the gate was reporting an IMPROVEMENT as a failure; and
  `tracker/g1-baseline`, committed at G1 as a drift tripwire, was referenced by
  NOTHING in tracker/tools and had never been checked.  It failed loudly (exit
  1) rather than passing silently, so nobody was misled — it had simply not
  been run since D3, which fits: G1 was signed off before D3 landed.
  **Repaired, and the number is re-established at HEAD: double run, 129 files,
  1447 signatures, EQUIVALENT, exit 0.**

  THE TRIPWIRE EARNED ITS KEEP ON ITS FIRST ARMING: 1447 signatures, exactly
  ONE differing — `lookbackJoin`, the documented solver-order-sensitive
  residual.  1446/1447 alpha-identical to the G1 baseline.  So the baseline is
  STALE (it predates Stage 1's pipeline replacement), not the tree drifted.
  Left ADVISORY rather than re-recorded: re-recording a golden is a Decision 9
  act and needs sign-off.  **That is the open gate question.**

  THE DESIGN, one line each.  Step 1: two representation-neutral wins
  (`Kind.subKind` has no empty-map fast path; `Vars.contains` materialises the
  whole variable vector on every occurs check) that cannot move a .ei byte and
  are measurable on [B]'s 1% floor.  Step 2: three counts that must precede any
  representation change — above all whether `restrictTypes` ever re-opens
  `instantiateType`'s boundness guard, because if it does, mutable cells are
  off the table in their simple form.  Step 3: lazy resolution with VALUE
  WRITE-BACK (not union-find path compression — the dominant cost is resolving
  structure, not walking chains), with `restrictTypes` SPLIT into a resolution
  set and a live scan set rather than removed.
  LEVELS ARE REFUSED for now, with a reason: nothing in the tree lowers levels
  on binding, Gamma demonstrably contains live metavariables, and `generalize`
  runs at App/Lam nodes rather than let-nodes, so a level predicate would
  silently over-generalize.
  Eight named sites would change an inferred TYPE rather than crash; each must
  be argued in the implementing commit.
  A SECOND QUADRATIC was found and is NOT inside the 42-44% figure:
  `instantiateKind` (Subst.scala:176) also rewrites the whole type map, reached
  from every `unifyType` variable case via `kindCheck` — Step 2(ii) counts it
  before anyone budgets for it.
  NEXT: Step 1, once the baseline gate question is answered.

- 2026-08-31 (P7 Step 0 baseline re-recorded, and Step 1 — six kept, one
  REVERTED by the gate on its first real use).

  BASELINE RE-RECORDED (signed off).  `tracker/g1-baseline` was cut with `run
  old` before D3 and had gone stale.  Re-cut from a full-inference run at
  3a2dd06, and the diff was small: only **6 of 129 interfaces** changed
  (Relation, Relation/Op, Relation/Predicate, Layout/Chart, Layout/Report,
  Layout/Column/Unsafe — all row-constraint-heavy), plus browse/groups.  The
  drift check is now a HARD GATE, and the README records that re-cutting is a
  Decision 9 act, never a way to make a red gate green.

  STEP 1, KEPT (6): physical-identity short-circuits in `ArrowK.subst`,
  `AppT.subst`, `AppT.map`, `VarT.subst` and `Memory.subst` — return `this`
  when nothing underneath changed, so an untouched subtree costs no allocation
  — plus `Vars.contains`, which was `exists(_ == v)` and therefore went through
  `ForeachIterable.iterator`, MATERIALISING the whole variable Vector before
  testing anything, on every occurs check.
  `VarT.subst` was the biggest: a variable NOT in the substitution still
  rebuilt a fresh `V` (a case class) inside a fresh `VarT` on every pass.
  DELIBERATELY NOT TOUCHED: `Forall`, `Exists` and `Part` all have NORMALISING
  smart constructors (Forall-of-Forall flattening, `Exists` dedup via
  `toSet.toList`, `Part` simplification), so returning `this` there would skip
  normalisation that happens today.

  STEP 1, REVERTED (1) — AND THIS IS THE REAL FINDING.  An empty-map fast path
  in `Kind.subKind`, mirroring the one `Type.subType` has had all along, is
  semantically a NO-OP and it still MOVED browse.txt.  Mechanism:
  `typeHasKindVars.sub(m,t)` is `t.map(_.subst(m))`, `Part.map` goes through
  `Part.apply`, and `Part.apply`'s foldLeft PREPENDS — so it REVERSES the RHS
  list every time it runs.  **The rendered order of a partition constraint is
  therefore a function of how many substitution passes happened to execute.**
  Skipping one no-op pass flipped the parity: `r <- (sr, xr, yr, o)` became
  `r <- (o, yr, xr, sr)` across every ChartMode-shaped signature.  All 1447
  signatures stayed ALPHA-EQUIVALENT, so only the browse byte-diff caught it —
  the artifact the hard gate had been armed for twenty minutes earlier.
  The revert carries the reason in place so it is not re-added.
  I HAD CLAIMED THESE CHANGES "CANNOT MOVE A .ei BYTE".  That was wrong, and
  the gate is what said so rather than a later session.

  NUMBERS.  Batch cold **11.50s** (5 reps, range 11.39-11.61) -> **11.14s**
  (10 reps, range 10.96-11.27); ranges disjoint, ~3.1%.
  CONFIRMED BY A PAIRED 10-vs-10 in one run, HEAD~1 against HEAD, each arm
  compiled and measured in sequence on the same machine: **11.51s ->
  11.14s = 0.37s, 3.2%**.  Two independent measurements agreeing to within a
  tenth of a point.  The paired arms' RANGES overlap (11.23-11.94 vs
  10.85-11.47) because the machine was far noisier by then — spreads 0.71/0.62
  against 0.22 in the morning — which is exactly why the harness reports
  MEDIANS and why Decision 3 says to say which statistic is being quoted.
  GATE: double run 1447 signatures EQUIVALENT, and no drift from the
  re-recorded baseline — exit 0.
  BASELINES: core/test 904 total, 903 pass, 1 fail (the known
  `Constraints.disjunction sound`).  The first run showed TWO failures; the
  protocol's single re-run showed only the known one, i.e. the documented
  concurrent-suite flake.  I did not capture the transient's name — my own
  grep filtered it — which is a gap worth not repeating.
  repl-smoke 4, lsp-smoke 82, boot 129, npm PASS.

  THIRD HARNESS BUG OF THE SESSION, found by the paired run refusing twice:
  perf-bench's concurrent-JVM guard was `pgrep -f com.clarifi.reporting.ermine`,
  and THE DOTS ARE UNESCAPED REGEX WILDCARDS — they match the SLASHES in
  `core/src/main/scala/com/clarifi/reporting/ermine/Type.scala`, so any process
  merely NAMING a source file trips it, including the paired script itself,
  which lists those paths in a variable.  It refused silently (no median in the
  output) rather than loudly.  Now escaped, and additionally required to match a
  `/java ` invocation so a shell that only mentions the class does not count.
  Companion to the stale-build guard that cried stale on a current tree (P5(a))
  and the negative debounce residual (P1): all three were guards or derived
  fields I added for good reasons that then produced false readings, and all
  three were caught by output that looked wrong rather than by an error.

  OPEN, AND IT IS A DECISION 9 QUESTION: make `Part.apply` ORDER-STABLE so the
  parity dependence disappears.  It is a latent fragility — the printed order of
  a partition is an artifact of pass count, not a property of the type — but
  fixing it moves .ei and browse bytes once, deliberately, and `Part.hashCode`
  depends on the RHS LIST order, which feeds the solver's priority-queue key
  (Constraints.scala:483).  So it could perturb solve order too.  Not bundled
  into a step whose whole premise was representation-neutrality.

- 2026-08-31 (P7 Step 2 — the three counts, and they clear the way).
  Temporary probe on `instantiateType`/`instantiateKind`/`restrictTypes` plus a
  per-env record of restricted keys, behind `-Dermine.p7probe`.  Instrumentation
  REMOVED in the same session that read it; the tree is back to HEAD.

  (i) THE GATING QUESTION: **`reopened = 0`.**  Over the whole 129-module
  interface-free load — 42,850 `restrictTypes` calls, 13,797 keys actually
  deleted — `instantiateType` was NEVER called on a variable its env had
  restricted.  Same on the editor path (111,305 restricts, 36,198 deletions,
  still zero).  So restrictTypes does not re-open the boundness guard in
  practice, and **retaining bindings for chain-chasing is NOT ruled out**: the
  design's own stated blocker is cleared.  Stated honestly: zero over this
  corpus is a measurement, not a proof — it is exactly the evidence the design
  asked for, and no more.
  Incidental: 2 of every 3 `restrictTypes` calls delete nothing.

  (ii) `instantiateKind` IS REAL BUT SECONDARY.  7,035 calls rewriting 716,017
  TYPE-map entries, **12.8%** of `instantiateType`'s 5,577,596.  So the second
  quadratic is worth about an eighth of the first, and the design was right to
  refuse to budget for it off the 42-44% figure, which never included it.

  (iii) THE M^2 TERM IS A BATCH PROBLEM, and this is the scoping result.
  Batch: 798 SubstEnvs, largest `hm.types` **1,578** entries, 18,939
  `instantiateType` calls at a mean map size of **294.5**, for **5.58M**
  map-entry rewrites — each one a full `Type.subst` traversal of that entry.
  Editor CHECKS (total minus the boot): 30,026 calls but only 190,394 entry
  rewrites, a mean map size of **6.3** — **46x smaller**.
  The reason is already in the tree: TolerantCheck gives every binding SCC its
  own SubstEnv (TolerantCheck.scala:246), which LSP 5.4 did for CORRECTNESS —
  a Death mid-component must not leave partial meta bindings on a shared env —
  and which incidentally solved the editor's M^2 problem years before anyone
  measured it.  **P7 is therefore a [B]-only item.**  Anyone hoping it would
  speed up the editor should stop: the editor's mean M is 6.

  WHAT THIS MEANS FOR THE PRIZE.  5.58M entry rewrites on the batch path, at
  ~21% of samples in substitution application and ~33% in free-variable
  collection.  If lazy resolution with write-back makes instantiation O(1)
  instead of O(map size), that is the term it removes.  Step 1 bought 3.2% by
  making each traversal cheaper; Step 3 would attack the number of traversals.
  NEXT: Step 3's design is already written above and now has its blocker
  cleared.  It remains a big change with eight named silent-divergence sites,
  so it wants its own gate before code.
