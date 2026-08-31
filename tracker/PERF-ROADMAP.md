# Ermine performance roadmap — loop state file

This file is the durable state for the /loop driving the performance work.
Each iteration: read this file, do the next unchecked item, verify every
baseline, commit with an iteration-log entry appended here and the checkbox
ticked.  A design fork not settled under "Decisions" goes under
"Blocked/Awaiting" and STOPS the loop.  Background and the original profile:
tracker/TICKET-perf-type-inference.md.  Editor-path measurements and the
machinery they came from: tracker/LSP-ROADMAP.md, Stage 2 (item 5.5 and the
G2 gate evidence).

Status: P1 DONE (2026-08-31).  G3-0 signed off; the harness exists and the
BASELINE OF RECORD is measured (see Baselines).  Nothing is optimized yet and
nothing may be until P2 (fresh profiles for both targets) reports.  NEXT: P2.

## The two targets

The ticket knows about one of these.  Stage 2 of the LSP work produced the
other, and it does not obey the ticket's headline finding.  EVERY checklist
item declares which target it serves, and what its ceiling is on the other.

**[B] BATCH LOAD** — loading the 129 stdlib modules with full inference.
MEASURED AT HEAD: **11.46s** interface-free, **5.59s** with the `.ei` cache
(medians of 5 fresh-JVM reps each, spread 0.11s and 0.17s; see Baselines for
the full line).  The inherited estimates were ~12s and ~6s, so they held.  The
JFR profile in the ticket attributes CPU samples — these are from 2026-08-30,
predate all of Stage 1 and 2, and P2 re-takes them:

| phase                                     | share |
|-------------------------------------------|-------|
| type/kind inference machinery             | 79.0% |
| parsing (layout, fixity, name resolution) | 18.7% |
| session driver / IO                       |  2.2% |
| term evaluation                           | ~0.1% |

Leaves: **free-variable collection** (`Type.vars` / `Vars.apply` and the kind
equivalents, rebuilding immutable Champ-trie hash sets while walking type
trees) is ~40% of ALL samples; **substitution application** (`HasTypeVars.sub`,
`VarT.subst`, `Type.sub`) is 10-15%.  Call paths: `Subst.inferBindingGroupTypes`
on 71% of stacks -> `inferAltTypes` -> `typeCheckExplicitBinding` ->
`inferType` -> `subsumeType`; `unifyType` and `instantiateType` ~23% each.
963 of 967 samples sit on one `ermine-session-task` thread.

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

- [ ] **P2 [B+E] Fresh profiles for both targets.**  No code changes; this item
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

- [ ] **P3 [B, ceiling ~10% on E] Free-variable collection** (ticket candidates
  1 and 5) — the ~40%-of-all-samples leaf.  Only if P2 confirms it.  In order,
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
  2).  Instrument first — a counter around `typeVars`/`sub` keyed by call site,
  run the 129-module load, and print the top call sites by count.  A guess about
  which of `subsumeType` / `instantiateType` / `inferBindingGroupTypes`
  recomputes the ftvs of the same type is not evidence; the counter is.  Then
  eliminate only the recomputation the counter proves is redundant within one
  binding group.  GATE: Decision 6.

- [ ] **P5 [E] The editor read path — the 0.80s the ticket does not know about.**
  Scoped by P2(b), not before.  What is already known and must be respected:
  parse+rename+lower runs WHOLE every check by design — LSP 5.5's review
  established that renamer binder ids and Lower's supply-minted Vs are FRESH
  EVERY RUN and shared across statements, so cached LOWERED trees cannot be
  mixed with a fresh run.  Reuse above that layer (surface statements keyed by
  extent text — the 5.5 fingerprint machinery already computes those keys) is
  the only safe shape without a stable-binder-identity scheme, and that scheme
  is explicitly a Blocked/Awaiting design item, not a side quest.  Also in
  scope, and cheaper: incremental didChange (sync kind 2) so a keystroke does
  not re-read 1757 lines of text before it re-parses them.  Split across
  commits; each one green.

- [ ] **P6 [E] The 300ms debounce, once compute drops below it.**  19% of the
  round trip today and pure policy.  When P3-P5 have moved compute, re-derive
  the debounce from the measured check cost instead of leaving it at the number
  5.3 picked.  Cheap, but LAST among the [E] items: shortening it while a check
  costs 1.27s just queues more work.

- [ ] **P7 [B] Substitution representation** (ticket candidate 3) — composing
  substitutions, or mutable metavariables with levels.  BIG.  DESIGN FIRST:
  write the design into this file (what replaces `HasTypeVars.sub`'s whole-tree
  rebuild, what happens to `Subst`'s existing structure, how `.ei` output stays
  byte-identical) and take it to Blocked/Awaiting for sign-off BEFORE writing
  code.  Do not start this before P3 and P4 have reported — they may take enough
  of the 10-15% that this stops being worth its risk.

- [ ] **P8 [B] Parallel module loading** (ticket candidate 4) — DESIGN ONLY
  until scoped, per Decision 10.  First deliverable is cheap and caps everything
  else: **measure the actual width of the 129-module dependency DAG by level**.
  If the graph is a near-chain, the ceiling is small and this item closes
  unstarted with a number.  Only if the width is real does the second
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

Known forks that will land in this section when reached: P7's design; P8's scope
if the DAG has real width; and the stable-binder-identity scheme that deeper [E]
reuse would need (named and deferred by LSP 5.5).

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
