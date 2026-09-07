# E1 REVIEW — `core/examples/Wide/`, its shared-file edits, and the MapView panic

Reviewer pass over stage E1 (report `tracker/loopmodel/E1-EXAMPLES.md`, 1,210 lines; group
`core/examples/Wide/`: 13 `.e` files + two `README`s, uncommitted; plus FIVE shared files it edited or
added that no other group was allowed to touch). Brief: `tracker/loopmodel/briefs/brief-E-review.md`
with `$STAGE = E1`, `$GROUP = Wide`, on top of `brief-E1.md` and `brief-E-common.md` (written after E1
started; its gates apply). Repository at `40f80aa` (branch `scala3-migration`), the three row-solver
defaults as adopted at `fe024a7`. Every `bin/ermine` below ran with
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM at a time, 2026-09-07, on a box
carrying three other agents (load average 5–7 through the session, so wall clocks are soft; solver
counts, interface counts and SQL row counts are exact). Scratch:
`/home/dmitry/.claude/jobs/880c725d/tmp/review-E1/`. Every `.ei` I caused was deleted. No commits, no
edits outside this file and that scratch directory. Findings are prefixed `N-`.



---

## 1. Verdict

**GROUP: FIX-THEN-ADVANCE.** The measurement is sound. Every solver, interface and timing number I
re-ran reproduces — the `.ei` sweep lands on **85 partition constraints across 19 of 24 signatures**
with all nine reports at **0**, per-helper counts identical to the report's list one by one; the
per-file own times land inside the report's brackets; the batch/per-file verdicts are 33 LOADED / 46
REJECTED / 0 UNKNOWN both ways; the three negatives are refused with exactly the recorded messages;
the differential is clean. The examples are good programs: `Leaderboard`, `TrialBalance` and
`WardRoster` are the kind of file a person learns a feature from, and the two runtime findings (the
`MapView` panic, the `emitOver` stub) are real, correctly diagnosed and worth more than the examples
themselves.

What must be fixed before commit is small and mostly prose, with one exception that is not prose:

* **N-1** the `TestSurfaceParsers` change is a *weakening*, not a strengthening — with the count
  derived from the same walk that feeds the loop, the assertion is implied by the failure list and
  the property now passes vacuously on an empty corpus, which is precisely what the literal 271
  caught. One extra line fixes it (§3.4).
* **N-2** `E1-EXAMPLES.md` §3b compares per-file against batch but never compares the batch against
  the *committed* script; nine pre-existing `shouldfail/` modules print a different refutation clause
  once `Wide/` joins the batch command line, one of them a different FIELD (§3.2).
* **N-3** three factual errors in files a reader reads: a stale filename in `TrialBalance.e`, a
  wrong cell count in `MediaSpend.e`, and "every helper here is applied to a 43-column row" in
  `ClaimsExperience.e` where two of them are applied to a 3-column `groupBy` result (§5).
* **N-4** the RUnion re-measurement is presented as a reproduction of the `Ai/README.md` figure. It
  is not: the README says "one small module" and never names it, so neither the 1.04 s nor the "does
  not finish" baseline is reproducible, and three E-stages have now produced three different
  reconstructions (§7).
* **N-5** the MapView fix is **not** one line: the same defect sits unfixed two and six lines below
  it, and with only `Lib.scala:988` patched `scalaRecordIn#` would fail on `scalaRecord#`'s own
  output. The blast radius in §7.2 is also short by six standard-library functions, including the
  record `Ord` (§6).
* **N-6** no `E1` row was added to `tracker/LOOP-MODEL-PLAN.md` (E2 and E3 both added theirs).

None of that requires touching a module body. The group and four of the five shared-file changes
should be committed after §11's list is applied.

### The findings, in one place

| # | finding | severity | where |
|---|---|---|---|
| N-1 | `TestSurfaceParsers`'s derived count is implied by the failure list, so the property now passes on an empty corpus | **must fix** | §3.4 |
| N-2 | adding `Wide/` to the batch moves nine pre-existing modules' refutation clauses, one of them the FIELD; the report never compares against the committed script | must record | §3.2 |
| N-3 | three factual errors in module headers (a stale filename, "six" cells for sixteen, "every helper" for two that are not) | must fix | §5.2, §5.3 |
| N-4 | the RUnion table is not a reproduction of `Ai/README.md`, and the "3–4×" bundling cost is contradicted by E1's own controlled experiment (1.2×) | must fix | §10 |
| N-5 | the MapView blast radius is six stdlib functions wider, `header#` is confirmed not guessed, and the fix is three `.toMap`s not one | must fix (report), ticket (code) | §6 |
| N-6 | no `E1` row in `tracker/LOOP-MODEL-PLAN.md` | must fix | §11.10 |
| N-7 | `sql-render.sh`'s name↔SQL mapping is positional and shifts silently if a probe name does not type-check | amend | §4, §14.1 |
| N-8 | `SqlRun.java` scrapes a jar out of `target/ermine-classpath`; `python3`'s stdlib `sqlite3` needs neither | amend | §4 |
| N-9 | `melt2` and `melt3` have no call site anywhere; `melt4`'s only call site is six columns wide, in a group about width | should fix | §7.2 |
| N-10 | no `Wide/Signatures.e` — the `xFull`/`xSimple` equivalence proof `brief-E-common.md` asks for | coverage gap | §7.3 |
| N-11 | the inferred `melt3` residual is 20 constraints here, 22 in the report — the published list is not canonical | note | §14.3 |

---

## 2. Shared files: a verdict for each

E1 is the only E-stage allowed to touch shared tooling, so these get the same scrutiny as the
examples. I diffed each against `2dd7dc3`, re-ran the pre-existing groups with the committed script
as a control, and checked the new tooling by reading it and running it.

| file | change | verdict |
|---|---|---|
| `tracker/tools/corpus-run.sh` | `Wide` + `Wide/shouldfail` in the file list, `Helpers.e` hoisted in both modes, header count 66 → 79 | **KEEP** — correct, minimal, mirrors the `Ai)` rule exactly; one behavioural side effect to record (N-2) |
| `tracker/tools/looptrace-corpus.sh` | `Wide Wide-shouldfail` in the default group list + two `case` arms | **KEEP** — correct; `-maxdepth 1` properly separates the two groups |
| `core/examples/README.md` | +25 lines, a new "Grouped example sets" section | **KEEP** — purely additive (the original ten lines are untouched); it will need a third row when `Algebra`/`Time`/`Present` land, which is the orchestrator's job |
| `scalacheck-binding/.../TestSurfaceParsers.scala` | `files ?= 271` → `files ?= moduleFiles.size` | **AMEND** — the maintenance trap is real and the fix direction is right, but as written the assertion is vacuous; add a floor (N-1, §3.4) |
| `tracker/tools/sql-render.sh` + `tsql2sqlite.py` + `SqlRun.java` + `wide-render-probe.{e,in}` | new: the SQL execution route | **KEEP, with two amendments** — a latent name-misalignment in the extractor and a JVM dependency that `python3`'s stdlib removes (§4) |

---

## 3. Gates re-run

| gate | report | mine | verdict |
|---|---|---|---|
| G1 per-file, 10 modules | 10 LOADED | **10 LOADED, rc=0, 0 `Unable to load`** | ✔ |
| G1 per-file own time | 0.29–2.83 s | **0.30–2.65 s**, same ordering | ✔ |
| G1 three negatives | 3 REJECTED, messages as in `RESULTS.md` | **3 REJECTED, messages byte-identical**, refused in 0.06 / 0.09 / 0.14 s | ✔ |
| G1 one batch, 79 files | 33 / 46 / 0, 29 s | **33 LOADED, 46 REJECTED, 0 UNKNOWN, 79 total, 32 s** | ✔ exact |
| G1 per-file vs batch | 7 of 79 differ, all message-only | see §3.2 — reproduced, plus a comparison the report did not make | ✔ + finding |
| G4(b) `.ei` | Helpers 24 bindings / 19 with partitions / **85**; nine reports **0** | **identical, binding by binding** (list below) | ✔ exact |
| G4(b) `.ei` determinism | "deterministic loader" | **two separate JVMs, `diff -rq` byte-identical** | ✔ |
| G2 differential `Ai` control | 83,942 segments 0/0/0 | **83,942 / agree 83,942 / skip 0** | ✔ exact |
| G2 differential `Wide` | 114,844 segments 0/0/0 | §3.5 | |
| G3 census | §4b table | §3.6 | |

### 3.1 Per-file own times (`Importing module 'Wide.X' (t)`, one JVM per file, `.ei` deleted first)

Helpers 0.38, SurveyPanel 0.30, BranchDeposits 0.58, RevenueShare 0.49, TrialBalance 0.50,
MediaSpend 0.52, Leaderboard 0.74, SalesLedger 1.30, WardRoster 2.27, ClaimsExperience 2.65.
Same two-slowest pair as the report (`WardRoster`, `ClaimsExperience`), same median (~0.5 s), nothing
near 30 s, no module needing `.slow`, and the batch own-times are uniformly lower
(0.20–2.04 s) because the session is warm. Confirmed.

### 3.2 N-2 — the batch comparison the report did not make

`E1-EXAMPLES.md` §3b compares the NEW per-file sweep against the NEW batch sweep and reports 7
message differences, 6 of them pre-existing. That is correct and I reproduce it. But the question a
shared-file edit raises is a different one: **does the batch behave the same as it did before `Wide`
was added to the command line?** I ran the committed `2dd7dc3` script (copied into scratch, only its
`here=` line changed) against the same tree, twice, and the new script twice.

```
new batch vs new batch (2 runs)     0 of 79 files differ
old batch vs old batch (2 runs)     1 of 66 files differ   (der04, a clause flip)
old batch    vs new batch          22 of 79 files differ   = 13 new files + 9 MESSAGE differences
```

The nine are `der04`, `der07`, `der08`, `dup02`, `dup03`, `inc04`, `inc05`, `mis01` (the refutation's
blame CLAUSE moves) and **`inf02`, where the reported FIELD moves**, `Shouldfail.Inf02.a` →
`Shouldfail.Inf02.b`. No verdict changes: 43 of 43 pre-existing REJECTED files stay REJECTED, every
`LOADED` stays `LOADED`, and every position (`file:line:col`) is unchanged.

Reading: this is the known blame instability (`TICKET-editor-and-solver-followups.md` item 4, and
`corpus-run.sh`'s own header) and NOT a new defect — `der04` flips between two runs of the *old*
script with no `Wide` anywhere, so the clause is not stable even at a fixed command line. E1's own
§7.5 diagnoses the mechanism correctly. But three things follow that the report does not say:

1. adding files to a batch command line **deterministically** reshuffles other modules' diagnostics
   (the new script is byte-stable across runs; the difference against the old script is systematic);
2. `inf02` shows the instability is not confined to the clause — the FIELD named can move too, which
   is a stronger statement than §7.5 makes and matters to anyone who pins a message;
3. nothing in the tree pins these strings (`core/examples/shouldfail/RESULTS.md` compares messages
   relatively, "same msg", never verbatim), so no recorded expectation is invalidated.

**Verdict: KEEP the `corpus-run.sh` change**; add these three sentences to `E1-EXAMPLES.md` §3b and
to `corpus-run.sh`'s header, which currently records the per-file-vs-batch measurement only.

### 3.3 The negatives

All three refused, per file and in batch, with the messages `Wide/shouldfail/RESULTS.md` records
verbatim:

```
pivot01 …:36:7: Fields appear twice in row: Wide.Shouldfail.Pivot01.period
win01   …:32:7: Row partitions are unsatisfiable at field 'Wide.Shouldfail.Win01.divisionName':
                the whole contains it but no part does           [per file]
                a part contains it but the whole does not        [in batch]
win02   …:36:7: Fields appear twice in row: Wide.Shouldfail.Win02.amount
```

Both `win01` clauses reproduce in the two modes, so §7.5's central piece of evidence — the same
module printing both clauses — is confirmed. The three cases are well chosen: each is caught by a
different constraint (`pivotBy`'s `r <- (k, v, i)` disjointness, `rankWithin`'s `r <- (w, o)`
containment, `windowed`'s `t <- (r, s)` union), each is a mistake a person makes, and `RESULTS.md`
explains why. This is the best-explained negative set in the examples tree.

### 3.4 N-1 — `TestSurfaceParsers`: the fix is a weakening, and one line repairs it

E1 is right about the trap. `files ?= 271` is a hard-coded corpus size that any added example breaks;
the corpus is **333 `.e` files** as I write (161 stdlib + 172 examples), so the constant is three
groups out of date and would have to be edited by every future E-stage. Deriving it is the right
direction.

But the derived form asserts nothing. Read the property's `match`: branches 1, 2 and 4 do
`files += 1`; branches 3 and 5 only append to `bad`. So **`failures.isEmpty` already implies
`files == moduleFiles.size`** — the second conjunct is a tautology given the first, and the whole
property collapses to `failures.isEmpty`. What the literal 271 bought, and this does not, is the
*floor*: if `moduleFiles` ever comes back empty or truncated — the JVM's working directory is not the
repository root, `core/src/main/resources/modules` has moved, a checkout is partial — then
`bad` is empty, `files` is 0, `expected` is 0, and **the property passes on a corpus of zero files**.
The old one failed loudly at `Expected 271 but got 0`.

That is exactly the failure mode this repository has already been bitten by and guards against
elsewhere: `corpus-verdicts.py` refuses to compare two all-`UNKNOWN` runs ("2026-09-02"),
`TestTolerantRead` uses `files.size >= 180`, and this very file's *second* property uses
`fixities > 30` and `statements > 1000`. So the report's sentence "It is also stronger than the
lower-bound idiom the sibling test already uses … which would tolerate a file being silently skipped"
has it backwards: against a silently skipped file the derived count is no better than `failures`
alone (a skipped file lands in `bad`), and against a vanished corpus the lower bound is strictly
better.

**Required amendment** — keep the derived equality (it documents the invariant and removes the
maintenance trap) and add the floor the file already uses elsewhere:

```scala
val expected = moduleFiles.size
(failures.isEmpty :| failures.take(6).mkString(" ;; ")) &&
  ((expected >= 250) :| s"only $expected corpus files found — sweep broken?") &&
  ((files ?= expected) :| s"$files of $expected files compared")
```

and delete the "stronger than the lower bound" sentence from the comment and from
`E1-EXAMPLES.md` §3d. `TestStatementExtents`'s three "(271 files)" property TITLES are labels, assert
nothing, and E1 was right to leave them; they should still be de-numbered when the orchestrator
consolidates.

---

## 4. The SQL rendering route — is it sound?

There is no `render` in this repository (finding §7.1, confirmed below), so E1 built one:
`wide-render-probe.e` binds `unsafePerformIO (dumpQuery <scanner> <relation>)` for each of 27
relations; `sql-render.sh` scrapes the resulting String out of the REPL transcript, runs it through
`tsql2sqlite.py` if it looks like T-SQL, and executes it with `SqlRun.java` against an empty in-memory
SQLite database. Because every Ermine relation literal compiles to a table-value constructor, the
queries are self-contained and need no schema — that is the insight the whole route rests on, and it
is a good one. **It is a stronger check than the REPL header dump the brief expected**, and it is the
only thing in the tree that executes a report's relational plan end to end.

**What it translates.** `tsql2sqlite.py` rewrites exactly two things, and its docstring says so
truthfully: (1) `(values (…),(…)) as lit([c1],…)` → `(select v1 as [c1], … union all select …) lit`;
(2) the emitter's missing space in `[col]desc` → `[col] desc`. Nothing else is touched — in
particular the `OVER (partition by … order by … rows between …)` clauses that the whole exercise is
about pass through verbatim, which is legitimate: I confirmed SQLite 3.45 parses them
(`select row_number() over (order by a) …` runs). The value-constructor rewrite is written carefully —
a real paren matcher and a quote-aware top-level splitter, not a regex — and it is correct on the
form the emitter produces.

**Where it can silently produce a wrong table — two amendments.**

* **N-7 (amend): the name↔SQL alignment is positional and can slip.** The extractor splits the
  transcript on `\n>> `, then `if not p.startswith('res'): continue` — a block that is *not* a `res`
  answer is skipped **without consuming a name**, while a block that *is* a `res` answer but contains
  `error:` or `Panic` **does** consume one. Any REPL response that neither starts with `res` nor is
  the `:load` echo (a warning line, a `Loaded N modules` straggler, a wrapped prompt) shifts every
  subsequent name by one, and the tool would then write real SQL under the wrong `q_*` name with no
  error anywhere. It happens to be aligned today; nothing checks that it is. The fix is to make the
  probe self-labelling — emit `"@@ <name>"` before each query from the `.in` file, or better, have
  the probe module bind a list of `(name, sql)` pairs — or, minimally, to assert
  `k == len(names)` at the end. Until then §6's fifteen tables are trusted on a positional argument.
* **N-8 (amend): `SqlRun.java` should be ten lines of `python3`.** The class does one thing —
  `executeQuery` one statement against `jdbc:sqlite::memory:` and print a table — and pays for it with
  a JVM start, a single-file-source compile, and `CP=$(tr ':' '\n' < target/ermine-classpath | grep
  sqlite-jdbc | head -1)`, an undeclared dependency on a file `bin/ermine` happens to have written. If
  `target/ermine-classpath` is absent or the jar name changes, `CP` is empty and `java -cp ''` fails
  per query with no diagnostic (`set -uo pipefail`, no `-e`). Python's stdlib `sqlite3` does the same
  job with no jar, no classpath and no JVM — I ran the same query shapes through it, including the
  `OVER` clause, in one command. As for "does `SqlRun.java` belong in `tracker/tools`": a 35-line,
  self-documenting, build-free file is not out of place next to the `.py` and `.sh` there, so this is
  a simplification rather than a rejection — but the classpath scrape is a real fragility and the
  python version has none of it.

Two smaller notes, neither blocking: the T-SQL/SQLite decision is `grep -q '\['` on the file, so a
SQLite-emitted query containing a bracket inside a string literal would be rewritten wrongly; and
`SqlRun` executes ONE statement, which is why anything whose plan materialises a temp table fails
(E1's limit 2, and the whole of E2's `closure` family).

### 4.1 The `SqlEmitter` join defect — confirmed, and it is the emitter's, not the route's

The E2 reviewer found that a join whose RIGHT operand is a join is emitted without parentheses. I
confirm the mechanism at the source: `SqlEmitter.scala:255-262` emits a join as

```scala
r1.emitSql(this) |+| raw(" ") |+| op.emit |+| raw(" ") |+| r2.emitSql(this) |+| " on (" |+| onExpr |+| ")"
```

— `r1` and `r2` are emitted bare, so `A ⋈ (C ⋈ D on c2) on c3` comes out as
`A join C join D on (c2) on (c3)`.

**Whose bug.** Two clauses, and E2's wording ("loses the grouping") is a shade too strong. In SQL-92 a
`<joined table>` is itself a `<table reference>`, so `A join C join D on c2 on c3` re-parses as
`A join (C join D on c2) on c3` — the grouping is recoverable, and T-SQL and Postgres accept it.
SQLite's join grammar is a **flat** list (`table-or-subquery (join-operator table-or-subquery
join-constraint)*`), so it cannot have two `ON`s stacked and rejects the text outright. I reproduced
both halves against SQLite 3.45:

```
A join B on … join C join D on … on …   →  sqlite3.OperationalError: near "on": syntax error
A join B on … join C on …               →  runs
```

So: **the emitter's bug**, and specifically a portability bug — `SqlEmitter` emits a form that is
standard but that `SqliteEmitter` cannot consume, and `SqliteEmitter` has the hook (it already
overrides plenty) to parenthesise a join operand that is itself a join. E1's route did not cause it
and did not hide it; it simply does not trip it, because every `Wide/` relation's join tree is
left-deep (`fact ** dim ** dim`). It bit E2 because `joinOnExactly`, `replaceColumn` and `**` against
an already-joined relation build right-nested trees. Ticket it against the emitter, with E2's
`q_inv_moves.lite.sql` as the reproduction.

---

## 5. The modules as programs

I read all thirteen `.e` files and both `README`s in full, and checked every rendered table in §6 of
the report against the inline data by hand.

**The data is real and the arithmetic is right.** This is worth stating first because it is the thing
that most often is not true of generated examples. `Leaderboard`'s three rendered tables reproduce
exactly from the nine inline rows and the two dimension tables — I recomputed the kill ranks
(North: vex 1204, kite 1188, nova 1120, sable 1041, orrin 903; South: rax, brant, tessel, quill), the
damage podium and all nine n-tile buckets, and every cell matches. `TrialBalance`'s running balance
(−412000, −800500, −776500, −1227700) and its three-period trailing mean (−400250, −258833.33,
−271900) are arithmetically correct. `RevenueShare`'s two levels of window total (Americas 93500,
EMEA 80000; Financial 61300, Healthcare 78700, Logistics 33500) are correct sums of the eight rows.
`WardRoster`'s cumulative overtime, ward agency totals and the 0.49 / 0.51 / 1.0 shares are correct.
`ClaimsExperience`'s ratios are correct. A reader can check these files by eye, which is the property
that makes an example teach.

**Header blocks.** All ten carry the Ai-style block: subject, fact table with its fields grouped by
kind, dimensions with their keys, helpers used, solver shapes exercised, and a `>>` recipe. The
fact-column counts (30, 27, 21, 21, 20, 24, 22, 23, 36) and joined-row counts (38, 35, 27, 26, 20,
30, 27, 26, 43) are all correct — I counted the fields in every record literal and every dimension.
Unlike E2's group, the printed `>>` recipes all name bindings that are unique across the directory,
so they survive a session with the whole group loaded.

### 5.1 The three best

**`TrialBalance.e`.** The clearest single-feature file in the directory and, I think, in the examples
tree. Its opening sentence says exactly why the feature exists ("each row's value depends on the rows
BEFORE it in a particular order, within a particular group"), the data is ten postings you can add up
in your head, both window steps differ only in the frame so the frame is isolated as the variable,
and the doc comment states the disjointness rule *and* names the negative module that violates it. It
is also the only module whose output a reader can verify without running anything.

**`Leaderboard.e`.** Five window functions, five one-line definitions, over a 38-column row — and the
claim it opens with ("not one of the five leaderboard columns names the other twenty-nine") is
demonstrated by the code rather than asserted. It also carries the two-column `thenBy` sort, the one
place `w` becomes a union of three rows. The 30-column fact table reads like a real table someone
would have.

**`SalesLedger.e`.** The pivot module, and the only place in the tree where a pivot does reporting
work. Two pivots on one ledger with a shared existential, a four-deep `Fulcrum`, and — the detail
that shows someone thought about the *report* and not only the types — two `Legend`s pinning the
column order, with a comment explaining that a pivoted table has no natural column order in its row
type. Its header is honest that the result is visible only as a type in this build.

### 5.2 The three weakest

**`SurveyPanel.e`** — the best *idea* in the directory (melt → aggregate → pivot back, the only place
one generative helper feeds another) executed against the group's own premise. The module declares a
20-column fact table and then projects it down to **six columns** before calling `melt4`:
`scored = response # {respondentId, waveId, scoreSpeed, scorePrice, scoreSupport, scoreQuality}`. So
the directory's only unpivot call site is the narrowest call site in the group, in a directory whose
subject is width, and `brief-E-common.md`'s rule ("a call site on a table with at least a dozen
fields somewhere in the group") is not met for `melt2`/`melt3`/`melt4` at all. The doc comment
defends the projection — "keeping the seventeen other columns would simply repeat them on all four
output rows" — but repeating the identity columns is precisely what a melt does and what `i` is for,
and keeping `countryCode`/`industryName` would have made the module's own promised analysis ("the
mean score by question and country", header line 3) actually writable; as it stands the module can
only group by wave. The table cell "joined row 20" is also not a joined row: nothing in the melt
pipeline joins.

**`ClaimsExperience.e`** — 242 lines for one measurement. The 36-column fact table is well made and
the "how wide can it get" question is worth asking, but every helper call in the file repeats a shape
already shown: `nTileWithin`/`denseWithin`/`topNWithin` are `Leaderboard` again, `withDerived3` is
`WardRoster` again, the defaulted pivot is `MediaSpend` again. The one new thing is the width, and
the header oversells it: **"Every helper here is applied to a 43-column joined row"** is false —
`pivotOnRowWithDefault`/`pivotByWithDefault` are applied to `byLobStatus`, a three-column `groupBy`
result. (N-3)

**`MediaSpend.e`** — its teaching point is the difference between a pivot with and without defaults,
and in this build that difference cannot be observed: both `spendByChannel` and
`spendByChannelFilled` panic when forced, so the reader sees neither the nulls nor the zeros. That is
not E1's fault, but it leaves `topChannels` — a repeat of `Leaderboard`'s `topNWithin` — as the only
part of the module a reader can run. And the header contains a wrong number: **"Five channels, three
months, two campaigns: six of the thirty cells have no row behind them"**. The fact table has
fourteen rows with fourteen distinct (campaign, month, channel) triples, so **sixteen** of the thirty
cells are empty, not six. (N-3)

### 5.3 Other defects in the prose a reader reads (all N-3)

* `core/examples/Wide/TrialBalance.e:156` points at **`shouldfail/RunningTotalOrderedByMeasure.e`**,
  which does not exist; the file is `Wide/shouldfail/win02_running_total_ordered_by_measure.e`.
* `BranchDeposits.e`'s "Helpers used" line lists `groupBy (stdlib)`, which the module never calls —
  `groupBy` appears only inside `latestPerKey`'s definition, in `Helpers.e`.
* `Helpers.e:81`'s doc comment for `thenBy` prints the example as
  ``desc points ` thenBy ' asc surname`` — the backtick/quote escaping is right for Ermine but reads
  as a typo in a doc comment; the code at `Leaderboard.e:187` uses the same spelling, so a reader can
  work it out, but a word of explanation would help.
* Three top-level binding names are defined in two Wide modules each (`ledger` in `SalesLedger` and
  `TrialBalance`, `accountDim` in `RevenueShare` and `TrialBalance`, `productDim` in `BranchDeposits`
  and `SalesLedger`), and eight field names likewise. Nothing breaks — the batch load is clean and no
  printed recipe touches an ambiguous name — but the group README tells the reader to load all ten at
  once, and `ledger` is then ambiguous. Worth one sentence in `Wide/README.md`, not a rename.

---

## 6. N-5 — the MapView panic: scope and the fix

This is the most valuable thing E1 found, and the diagnosis is right in its essentials. Two
corrections: the blast radius is bigger, and the fix is not one line.

### 6.1 The mechanism, confirmed at the source

`Lib.scala:986-990`

```scala
primOp(Global("Native.Record","record#"), Fun(x => x.whnfMatch("Native.Record.record#") {
       case t@Rec(m) => try { Prim(m.mapValues(_.whnf)) } catch { … }
     }), FAR(a => recordT(a) ->: rec))
```

`Lib.scala:1005-1009`

```scala
primOp(Global("Native.Record", "scalaRecord#"),
       Fun(x => x.whnfMatch("Native.Record.scalaRecord#") {
         case Prim(t: Map[String, Runtime]) => Prim(t mapValues (toPrimExpr(_)))
       }), rec ->: scalaRec)
```

Since 2.13 `Map#mapValues` returns a lazy `MapView`, which is not a `Map`, so `record#`'s answer
never matches `scalaRecord#`'s only case and `whnfMatch` panics. The repository already knows this
class of site: `record/RecordMap.scala:25` carries the comment
*"2.13's `mapValues` and `filterKeys` return lazy views rather than maps"*, and
`tracker/tools/fix_mapvalues.py` exists for it. Every other `mapValues` I grepped in
`core/src/main/scala` (34 of them) ends in `.toMap`; **these two, and `scalaRecordIn#` at :1012, are
the exceptions.**

**Runtime confirmation** (`bin/ermine <scratch>/MapProbe.e`, one JVM, four expressions):

```
>> probeRecord        res0 : Record# = MapView(<not computed>)
>> probeScalaRecord   res1 : ScalaRecord# =
     <error: Panic: unexpected runtime value in Native.Record.scalaRecord# - MapView(<not computed>)>
>> probeHeader        res2 : Row (|w, q|) = (Row
     <error: Panic: unexpected runtime value in Record.header# - MapView(<not computed>)>)
>> probeAll           res3 : Predicate (|q|) =
     <error: Panic: unexpected runtime value in Native.Record.scalaRecord# - MapView(<not computed>)>
```

and, forcing the pre-existing example's own pivot,

```
>> pivotData     <error: Panic: … Native.Record.scalaRecord# - MapView(<not computed>)>
>> pivotData2    <error: Panic: … Native.Record.scalaRecord# - MapView(<not computed>)>
```

Note the third line: **`header#` is not a guess — `Record.header` panics too**, with its own message.
§7.2 hedges ("presumably in the same position, though nothing here forced it"); it can be stated as
fact. Note also the last two: `core/examples/PivotTest.e`, which has been in the tree the whole time,
cannot have its result forced either — E1 is right that laziness is why nobody noticed.

### 6.2 The blast radius is six functions wider than §7.2 says

§7.2 names `Relation.Pivot.pivot`, `pivotWithDefault`, `Layout.Report.pivotTabular`,
`Fulcrum/Legendary.e` and `Relation.Predicate.all`, and guesses that `header#` "is presumably in the
same position, though nothing here forced it". Grepping every consumer of `record#` / `scalaRecord#`
/ `header#` in `core/src/main/resources/modules` gives a longer list, and `header#` is not a guess —
it has a live caller:

| stdlib function | site | why |
|---|---|---|
| `Record.header : {..r} -> Row r` | `Record.e:24` | `header# . record#` — `header#` (`Lib.scala:1016`) matches `Prim(r: Map[String,Runtime])`, same pattern, same failure |
| `Record.anyRecordOrd : Ord {..r}` | `Record.e:21` | `contramap (scalaRecord# . record#) anyRecordOrd##` — **the record `Ord`** |
| `Relation.Sort.partialRecordOrd` | `Sort.e:109` | `contramap (scalaRecord# . record#) . fromOrd#` — the record comparator used for sorting |
| `Relation.nonEmptyRelation` | `Relation.e:33` | `mkRelationWithHeader# (header#_Rec . record#_Rec $ r) …` |
| `Layout.Chart.srecKeys` | `Chart.e:188` | `part (scalaRecord# . record#)` |
| `Layout.Presentation` (`extract#` path) | `Presentation.e:82` | `extract# pr' . scalaRecord# . record#` |
| `Relation.Predicate.all` | `Predicate.e:77` | as §7.2 says |
| `Relation.Pivot.pivot` / `pivotWithDefault` | `Pivot.e:112,116` | as §7.2 says |

`Relation.relation` is **not** affected (`relation r = mkRelation# (toList# r)`, `Relation.e:24`),
which is why the 15 SQL renderings work at all — worth saying explicitly, because "record# is broken"
would otherwise read as "no relation literal can be forced".

### 6.3 The fix is not one line

The report says "*The fix is one character-sequence, `.toMap` at `Lib.scala:988`*". Patching only 988
makes `scalaRecord#` **match**, and it then answers `Prim(t mapValues (toPrimExpr(_)))` — a
`MapView` again, published at type `ScalaRecord#`. Its own consumer two lines down,

```scala
primOp(Global("Native.Record", "scalaRecordIn#"),
       Fun(x => x.whnfMatch("Native.Record.scalaRecordIn#") {
         case Prim(t: Record) => Prim(t mapValues (fromPrimExpr(_)))   // Record = Map[ColumnName,PrimExpr]
       }), scalaRec ->: rec)
```

matches on `Map` in exactly the same way and would panic on it — and `scalaRecordIn#` is live, at
`Layout/Report.e:1594` and `:1608`. Downstream of `pivot#`, `km.extract[List[(Record, …)]]` is an
unchecked `asInstanceOf`, so a `MapView` would travel into `PivotE`'s map and surface as a
`ClassCastException` at whatever first uses it as a `Map` rather than as a panic with a message.

**The correct minimal fix is three `.toMap`s: `Lib.scala:988`, `:1007` and `:1012`.** `header#`
(:1016) already has one on its result and needs none. I have not applied it (per the brief), and I
have not compiled, so "three" is a static claim; the point is that "one line" understates it and a
fix stage that applies only 988 will find the next panic immediately.

### 6.4 Why nothing caught it

E1's explanation is right and worth keeping: `PivotTest.e` never forces `pivotData`, Ermine is lazy,
`:load` type-checks without evaluating, and nothing in `core/test` evaluates a pivot. The right
follow-up is not only the `.toMap`s but **a test that forces one** — three lines in `core/test`
evaluating `PivotTest.pivotData` would have caught this and will catch the next one.

---

## 7. Coverage against the briefs

### 7.1 What the briefs asked for and got

`brief-E1.md` E1.2 lists eight subjects the group must cover between them. All eight are there, and
two modules are extra:

| asked for | delivered |
|---|---|
| a wide sales ledger pivoted by period AND by product line, two Fulcrums, one nested in a Keyed report | `SalesLedger.e` — two Fulcrums, `tabular_K` with `Legend`s ✔ |
| a trial-balance / GL with running balances (framed window) | `TrialBalance.e` ✔ |
| a leaderboard with rank/dense/nTile within groups over a 30-field player table | `Leaderboard.e`, exactly 30 fields ✔ |
| a time-series with moving averages and `lookupLatest` joins across two calendars | `BranchDeposits.e` ✔ |
| a wide survey table melted then pivoted back | `SurveyPanel.e` ✔ (but see §5.2) |
| a share-of-total with window totals at two levels | `RevenueShare.e` ✔ |
| a report composing three generic helpers whose residual rows chain | `WardRoster.e` — four ✔ |
| one `shouldfail` module misusing a helper | three ✔ |
| — | `MediaSpend.e`, `ClaimsExperience.e` |

`Relation.Windowed` had **zero** callers anywhere in `core/examples` at `2dd7dc3` (I checked with
`git grep` against the commit) and `Relation.Pivot` had exactly one, `PivotTest.e`. Both premises of
the brief are true and both gaps are now closed.

### 7.2 N-9 — two helpers are never instantiated, and the unpivot family is never instantiated wide

`brief-E-common.md` requires of every helper "a call site on a table with at least a dozen fields
somewhere in the group". Stripping comments and string literals and searching all thirteen modules:

* **`melt2` — no call site at all.**
* **`melt3` — no call site at all.** This is the one whose signature the report analyses at greatest
  length (§2's "small-signature surprise", §7.6's inferred-vs-annotated comparison, the "elevenfold
  reduction" claim); the group publishes its residual but never checks a single instantiation of it.
* `melt4` — one call site, on a **six-column** relation (§5.2).

So the entire unpivot family — three of the 24 helpers, and one of the three subjects the group's own
README advertises — is exercised at the definition site only, and the one call site is the narrowest
in the directory. Every other helper has at least one call site on a 20-column-or-wider row.

**Fix:** widen `SurveyPanel.scored` to keep two or three profile columns in the identity (which also
makes the module's promised "mean score by question and country" writable), and add one `melt3` or
`melt2` call — `TrialBalance`'s `debitAmt`/`creditAmt` melted to a `side`/`amount` pair on the
27-column ledger would do it in three lines and is a real report step.

### 7.3 N-10 — no `Signatures.e`, so the `xFull`/`xSimple` proof is missing

`brief-E-common.md` asks each group to do what `core/examples/incomplete/Signatures.e` does — write a
residual signature by hand and prove it equivalent — "for at least two of your helpers (an
`xFull`/`xSimple` pair)". E2 shipped `Algebra/Signatures.e` (16 bindings, 31 published partitions) and
E3 shipped eight entailment proofs. **`Wide/` has no such module.** The report discusses the idea in
prose (§7.6's inferred `melt3`) but ships no module that checks it, so the claim is unverifiable from
the tree and the group misses the one thing that would make its "the annotation is an elevenfold
reduction" headline reproducible by a reader.

In fairness: `brief-E-common.md` was written after E1 started, and `brief-E1.md` does not ask for it.
I record it as the largest *coverage* gap rather than as a defect, and it is one module's work —
`Wide/Signatures.e` with `melt3Full`/`melt3Simple` and `withDerived2Full`/`withDerived2Simple` would
close it and would give the group its missing `melt3` call site at the same time.

### 7.4 Smaller gaps

* `brief-E1.md` E1.1 asks for "a `lookupLatestBy` over a generic key". What shipped is
  `latestPerKey` (`groupBy ks (maxRowBy dF)`), which is a per-key argmax, not an as-of join; the
  as-of join is done by calling the *stdlib* `lookupLatest` directly in `BranchDeposits.e`. That is a
  reasonable substitution and the module exercises the heavy stdlib body either way, but the helper
  the brief named does not exist and the report does not say so.
* `Relation.Aggregate` is imported by nine of the ten modules and used only through `sumBy`/`meanBy`
  in `groupBy`; `Relation.Windowed`'s `fancyWindow` (window functions over *Ops* rather than columns)
  is untouched, and so is `Layout.Report.pivotTabular`, the dynamic-pivot path §7.6 describes. The
  last is correctly excluded (it needs a live `Scanner`); the first two are follow-up material.

---

## 8. The findings about Ermine — confirmed or refuted, one by one

| # | E1's finding | my verdict |
|---|---|---|
| 7.1 | `render` does not exist; no concrete `Writer` ships in this repo | **CONFIRMED** (§8.1) |
| 7.2 | `Relation.Pivot.pivot` and `Relation.Predicate.all` panic when forced | **CONFIRMED**, scope understated, fix understated (§6) |
| 7.3 | window functions emit real SQL only on the MS SQL emitter | **CONFIRMED** (§8.2) |
| 7.4 | `dumpQuery` cannot dump a `Mem`, nor `lookupLatest`'s temp table | **CONFIRMED** (§8.3) |
| §5 | the RUnion cliff has moved — the bundled form finishes | **CONFIRMED as a fact, REFUTED as a reproduction** (§9) |
| §5b | `share` is cheaper than `windowTotal`-then-divide | see §9.2 |
| 7.5 | the refutation clause is a propagation reason, not a description | **CONFIRMED, and strengthened** — the FIELD can move too (§3.2) |
| 7.6 | a variadic `melt` and a relation-level dynamic pivot are inexpressible | **CONFIRMED** (§8.4) |
| 7.7 | `seq` and `currency` collide with stdlib terms | **CONFIRMED** (§8.5) |
| §3d | `TestSurfaceParsers` asserts an exact corpus size | **CONFIRMED**, fix amended (§3.4) |

### 8.1 No `render`

`grep -rn '^render *[:=]' core/src/main/resources/modules` returns nothing;
`grep -n '"render"' …/session/Console.scala` returns nothing. `Layout/Writer.e` declares
`foreign data "com.clarifi.reporting.writers.Writer" Writer` and
`writers/Writer.scala` in this repository has only the abstract class — every concrete writer is in
the separate `ermine-writers` project, which is not on this build's classpath. Confirmed statically;
confirmed at runtime in §8.6. E1 was right to drop `render` from the `Wide/` headers, and right that
this is a **pre-existing documentation error in `core/examples/Ai/*.e` and `Ai/README.md`**, which
still tell a reader to type it. E3's report reaches the same conclusion independently.

### 8.2 `emitOver`

`SqlEmitter.scala:269-271` is

```scala
def emitOver(e: SqlExpr, over: SqlOver): RawSql =
  "TODO I don't yet know how to play %s over %s".format (e.emitSql(this), over)
```

and `EmitOver_UsingOver` (`:538-577`) is mixed in by exactly one emitter, `MsSqlEmitter` (`:832`).
`SqliteEmitter` (`:665`), `MySqlEmitter`, `PostgreSqlEmitter` (`:941`) and `VerticaSqlEmitter`
inherit the stub. Confirmed, and E1's characterisation is the important part: **this is a silent
wrong answer, not an error** — the sentence is spliced into the SQL text and fails at the database,
or worse, in a dialect where it happens to parse. Postgres has had `OVER` since 8.4 (2009) and SQLite
since 3.25 (2018), so the stub is stale rather than a capability gap. Highest-value ticket in the set
after the panic.

### 8.3 `dumpQuery` on a `Mem` and on `lookupLatest`'s temp table

Confirmed at runtime (§14.1): four of the 27 probed relations answer
`<error: Don't know how to dump a mem.>` and two answer
`<error: Emission not supported for sql statement SqlLoad(TableName(t…))>`, and they are exactly the
six the report names. `Scanner.scala:33-35` is `def dumpMem(…) = sys.error("Don't know how to dump a mem.")`, with no
`SqlScanner` override; the sibling `dumpRel` just above it is the same shape. E1's framing is right and matters: these are limits of
*dumping*, not of execution — a real `Scanner` against a database would materialise the temp table
and scan the `Mem`. They bite here only because dumping is the only execution this repository has.
Worth noting for the orchestrator: this bites `Algebra/` much harder than `Wide/` (E2's review: every
`groupBy` result in that group is a `Mem`), so it is a shared-tooling limit and not a `Wide/`
peculiarity.

### 8.4 The two inexpressible shapes

E1's §7.6 argument is correct and worth keeping verbatim in a ticket. `Row r` is a *runtime* value
(`Row (List (String, PrimT))`) whose *type* is opaque, so no construct folds over the fields of an
abstract row at the type level, and each `melt` arm needs one `except`/`combine`/`rename` and one
union per melted column — hence fixed arity. For the pivot direction, `Relation.Pivot.pivot` needs a
`Fulcrum k v p` with a type-level `p`; the dynamic path exists only at report level, and I confirm
its shape: `Layout/Report.e:732` `data PivotSpec k v = forall s. PivotSpec (Legend s) (Row s)
(Fulcrum k v s)`, built by `dynamicPivot`/`dynamicPivot'` (`:737`, `:741`) and consumed by
`pivotTabular` (`:770`), which opens with `orderedScanner srt (project kr rel) go` — a live `Scanner`,
hence unusable in a self-contained example here. **"static columns → relation-level pivot; dynamic
columns → report-level pivot, and no way to get a relation back out"** is exactly right and is the
single most useful sentence in the report for a future user.

### 8.5 `seq` and `currency`

`Function.e:50` `seq : a -> b -> b` (re-exported by `Prelude`); `Layout/Report.e:163`
`currency : String -> Double -> Report f z`, plus `Layout/Format.e:80` and
`Layout/Presentation.e:65`. Confirmed. E1's grep recipe
(`grep -rlE '^<name> *(:|=)' core/src/main/resources/modules/`) works and is worth putting in a style
note. This is a diagnostics complaint rather than a bug: the error lands on the record literal, several
lines from the `field` declaration, and never mentions the collision.

### 8.6 `render`, at runtime

In the same REPL session that ran all ten header recipes (§14.2), with every `Wide/` module loaded:

```
>> render leaderboardReport
runtime error: <interactive>:1:1: error: undefined term
```

Confirmed. E1's decision to leave `render` out of the `Wide/` headers and to say so in
`Wide/README.md` rather than quietly imitating the Ai headers is the right call, and the finding
should be ticketed against the *Ai* headers.

---

## 9. The differential and the census — every cell reproduced

`LOOPTRACE_GROUPS="boot Ai Wide Wide-shouldfail" tracker/tools/looptrace-corpus.sh`, on the tree as
E1 left it, in one session:

```
boot             segments=54199   agree=54199  skip=0 hashdiff=0 eqdiff=0 nonpart=?     rejected=0 fuel=0
Ai               segments=83942   agree=83942  skip=0 hashdiff=0 eqdiff=0 nonpart=1646  rejected=0 fuel=0
Wide             segments=114844  agree=114844 skip=0 hashdiff=0 eqdiff=0 nonpart=1483  rejected=0 fuel=0
Wide-shouldfail  segments=55775   agree=55775  skip=0 hashdiff=0 eqdiff=0 nonpart=1094  rejected=1 fuel=0
```

**Exact**: 114,844 and 55,775 segments, `nonpart` 1,483 and 1,094, `rejected=1` on the negatives —
every figure in `E1-EXAMPLES.md` §4a, to the digit, including the one model refutation that agrees
with the compiler. Model time 474 s for `Wide` against 26 s for `Ai` — the report's "24× slower per
segment on the new group" reproduces (5.5 ms vs 0.31 ms per segment; I measure 4.1 ms vs 0.31 ms,
the difference being machine load, and the ratio is the point).

### 9.1 The census

`lake exe looptrace --replay <trace> --depth`, summarised by location (`core/examples/Ai/`,
`core/examples/Wide/`), which is the report's own method.

| | `Ai` (report / mine) | `Wide` (report / mine) |
|---|---|---|
| solves located in the group | 20,393 / **20,393** | 45,778 / **45,778** |
| verdicts | all SOLVED / **all SOLVED** | all SOLVED / **all SOLVED** |
| steps max / mean | 137 / 0.49 → **137 / 0.49** | 249 / 0.39 → **249 / 0.39** |
| nvars max | 11 / **11** | 21 / **21** |
| nparts max | 7 / **7** | 14 / **14** |
| nlbl max | 14 / **14** | 46 / **46** |
| draws (total) max / mean | 52 / 0.06 → **52 / 0.062** | 77 / 0.03 → **77 / 0.034** |
| draws in the LOOP, >0 on | 185 (0.91 %) / **185 (0.91 %)** | 165 (0.36 %) / **165 (0.36 %)** |
| vocabulary-fixed | 99.09 % / **99.09 %** | 99.64 % / **99.64 %** |
| chain depth max | 3 / **3** | 3 / **3** |
| depth histogram | 0:20208, 1:153, 2:31, 3:1 → **identical** | 0:45613, 1:116, 2:41, 3:8 → **identical** |
| `SplitConcrete` total / max | 303 / 8 → **303 / 8** | 396 / 14 → **396 / 14** |
| `Resolution` total / max | 525 / 41 → **525 / 41** | 811 / 62 → **811 / 62** |
| generative rules fired on | 185 (0.91 %) / **185** | 165 (0.36 %) / **165** |
| maxdkey / remint / cremint | 8 / 1 / 5 → **8 / 1 / 5** | 8 / 3 / 7 → **8 / 3 / 7** |
| budget headroom (largest draw) | 52 (0.26 %) / **52** | 77 (0.385 %) / **77** |

And the third column, `Wide/shouldfail` (E1's filter is `core/examples/Wide/`, which in that group's
session includes `Helpers.e`): report 910 solves / 909 SOLVED + **1 REJECTED** / steps 29 / nvars 20 /
nparts 9 / nlbl 4 / draws 5 / loop draws on 6 (0.66 %) / vocabulary-fixed 99.34 % / depth hist
0:904, 1:6 / `SplitConcrete` 10 max 3 / `Resolution` 3 max 3 / maxdkey 2, remint 1, cremint 1 —
**mine: identical, every cell.** One presentational note: 837 of those 910 solves are `Helpers.e`
being re-checked in that session, and only **73** come from the three negative modules themselves
(72 SOLVED + the 1 REJECTED, steps 26, nvars 11, nparts 6, all six loop draws). The column is
therefore mostly a second sample of the library, not a census of the negatives; that is E1's method
applied consistently (the `Wide` column includes `Helpers.e` too), but the report should say which
number is which.

**Not one cell differs.** A note for whoever reads the table next, because it cost me an hour: the
trace's `drawn0` is the supply count *at loop entry*, so LOOP draws are `drawn - drawn0`
(`tracker/lean/Rowpartition/Loop/Policy.lean:337`); computing "loop draws > 0" as `drawn0 > 0`
gives 293 / 237 and a wrong vocabulary-fixed fraction. E1 used the right definition.

One observation the report does not draw out, which its own numbers establish: in both groups
**"a draw in the loop" and "a generative rule fired" are the same 185 and the same 165 solves.**
That is not a coincidence of presentation — `SplitConcrete` and `Resolution` are the only rules that
mint, so the two rows are the same predicate, and the identity holds on 66,171 solves here. Worth one
sentence in the report; it makes the "vocabulary-fixed" column and the "generative rules" column the
same measurement seen twice.

### 9.2 The reading of the census — agreed, with one qualification

The report's headline, "**size, not depth**", is right and well argued: 21 vars against 11, 14
partitions against 7, 46 labels against 14, 249 steps against 137, 77 draws against 52,
`Resolution` 62 in one solve against 41, and eight solves at depth 3 against one — all reproduced —
while the depth ceiling stays at 3. Its honesty about what it did *not* find (no deeper chain, no
re-mint beyond 8, nothing within two orders of magnitude of the budget) is exactly the right posture
and matches what E2's and E3's censuses found in their groups.

The qualification is about the depth-3 comparison. "Eight solves at depth 3 against one — a 3.6×
higher rate" is arithmetically right (8/45,778 vs 1/20,393) but rests on **one** solve in the control;
one solve is not a rate. The defensible statement is "the old corpus reaches depth 3 once, the new one
eight times", and the report should stop there rather than computing a ratio from a denominator of
one.

---

## 10. N-4 — the RUnion re-measurement: right conclusion, wrong provenance, wrong multiplier

### 10.1 What reproduces

I rebuilt E1's three forms exactly as §5 describes them — three copies of
`core/examples/Ai/SupplyChainInventory.e`, identical but for the module name and the definition of
`labelled` (A: inline `combine_Op (if_Op …)`; B: `Ai.Common.withColumn`; C: E1's
`withConditionalColumn`, whose signature bundles `RUnion3 v r s t` with `RUnion2 out rin c`) — and
loaded each behind `Ai/Common.e`, one JVM each, twice:

| form | E1 run 1 / run 2 | mine run 1 / run 2 | loads? |
|---|---|---|---|
| A inline | 1.46 / 1.05 s | **1.06 / 1.08 s** | yes |
| B via `withColumn` (one `RUnion2`) | 1.12 / 1.11 s | **1.09 / 1.06 s** | yes |
| C bundling `RUnion3` + `RUnion2` | 1.30 / 1.51 s | **1.28 / 1.27 s** | **yes** |

**The headline is confirmed: the form `Ai/README.md` records as "does not finish" finishes, in about
1.3 s, on the module E1 used.** That is a real and important result, and it is the reason
`Wide/Helpers.e` can ship `withDerived2` and `withDerived3` at all.

### 10.2 What does not reproduce, and should not be claimed

**(a) It is not a reproduction of the README's measurement.** `Ai/README.md` says the three rows were
measured "on one small module" and **never names the module**. `SupplyChainInventory.e` is not a small
module, and the report's own check that it is the right one — "Form A reproduces the README's 1.04 s
to two figures" — does not survive a quieter machine: I get 1.06/1.08 s for form A, which does match
1.04 s, but E1's *own* second table ("the same three forms on a smaller module") gives form A at
0.29/0.36 s, which does not. Two reconstructions of the same baseline that differ by 3× cannot both
be the original. E3's report gives a third set of figures (1.04 → 0.17 s, "does not finish" → 0.12 s)
and the E2 reviewer records that the figure "does not reproduce at either configuration". **Three
E-stages, three reconstructions.** The honest statement is: *the bundled form now finishes; the
README's baselines are not reproducible because the module they were taken on was never recorded.*

**(b) The "bundling still costs 3–4×" claim is contradicted by E1's own controlled experiment.**
§5's "What this changes, and what it does not" argues the advice survives because
`WardRoster` (2.13 s) and `ClaimsExperience` (2.60 s) are "the two slowest in the group, at 3–4× the
group's median (0.60 s)". The report itself flags that this is "not a controlled comparison — they
differ in more than bundling", and it is worse than uncontrolled: `ClaimsExperience` also carries the
widest row in the corpus and three window helpers and a defaulted pivot, and `WardRoster` also carries
a four-link chain. The *controlled* comparison is the A/B/C table above, where the only thing that
changes is the bundling, and it says **1.2×** (1.27 / 1.07), not 3–4×. E1's own small-module table
says ~2× (0.51–0.83 against 0.29–0.36). So the rule is right — bundle last — but the multiplier that
`Wide/README.md`, `Helpers.e`'s header and `E1-EXAMPLES.md` §5 all quote is an artefact of comparing
two modules that differ in four ways.

**Fix:** in all three places, replace "bundling still costs 3–4×" with the controlled number
("1.2× on `SupplyChainInventory`, ~2× on a nine-column module") and drop the
`WardRoster`/`ClaimsExperience` comparison, or keep it explicitly labelled as an observation about
those two modules rather than about bundling.

### 10.3 `share` versus `windowTotal`-then-divide

The report's second "measured the other way round" claim: `share` (one call, whose `Op` carries
`(/_Op)`'s `OpBin` lattice on top of a window's minted row) at 0.05–0.06 s against
`windowTotal`-then-`combine` at 0.08–0.09 s, "on a 6-column row and on a 26-column one alike". I
re-ran the six-column half as a controlled pair — two scratch modules identical but for the
spelling of the one definition, three runs each, behind `Wide/Helpers.e`:

| form | run 1 | run 2 | run 3 |
|---|---|---|---|
| `share {regionName} mrr pct book` | **0.08 s** | **0.08 s** | **0.07 s** |
| `windowTotal` then `combine_Op (col mrr /_Op col tot)` | **0.15 s** | **0.10 s** | **0.11 s** |

**CONFIRMED**: the one-call spelling wins every run, with no overlap between the two sets, at a ratio
of 1.3–1.9× against the report's 1.5–1.6×. The absolute numbers are higher than E1's (0.05–0.06 /
0.08–0.09) because the relations are not the same, but the direction and the size of the effect
reproduce. The structural conclusion the report draws from it — *the solver's cost tracks the
constraint set, not the row* — is supported here and independently by the census (`ClaimsExperience`
carries 43 columns at 2.65 s while `Leaderboard` carries 38 at 0.74 s, and the difference is
`withDerived3`). This is the one measurement in §5 that needs no qualification.

---

## 11. Required fixes before commit

Ordered by cost. None touches a module body except the two in item 5.

1. **`TestSurfaceParsers.scala`** — add the floor (§3.4's three-line form) and delete the "stronger
   than the lower bound" sentence from the comment and from `E1-EXAMPLES.md` §3d.
2. **`E1-EXAMPLES.md` §3b + `tracker/tools/corpus-run.sh` header** — record §3.2: the batch's
   diagnostics for nine pre-existing `shouldfail/` modules move once `Wide/` is on the command line,
   one of them changing the FIELD (`Inf02.a` → `Inf02.b`); no verdict, position or `RESULTS.md`
   expectation changes; and the old script is itself unstable on `der04` across two runs.
3. **`core/examples/Wide/TrialBalance.e:156`** — `shouldfail/RunningTotalOrderedByMeasure.e` →
   `shouldfail/win02_running_total_ordered_by_measure.e`.
4. **`core/examples/Wide/MediaSpend.e`** header — "six of the thirty cells have no row behind them"
   → **sixteen** (14 fact rows, 14 distinct campaign×month×channel triples, 30 cells).
5. **`core/examples/Wide/ClaimsExperience.e`** header — "Every helper here is applied to a
   43-column joined row" is false for `pivotOnRowWithDefault`/`pivotByWithDefault`, which are applied
   to the three-column `byLobStatus`. Say "every window and derived-column helper".
6. **`core/examples/Wide/BranchDeposits.e`** header — drop `groupBy` from "Helpers used"; the module
   never calls it.
7. **`E1-EXAMPLES.md` §5** — stop presenting the RUnion table as a reproduction of `Ai/README.md`'s
   figures (§10). State what is true: the bundled form finishes; the README's module is unrecorded so
   its 1.04 s / 0.50 s / "does not finish" baselines cannot be reproduced; three E-stages have
   produced three different reconstructions.
8. **`E1-EXAMPLES.md` §4b** — drop the "3.6× higher rate" at depth 3 (denominator of one, §9.2); add
   the two sentences about `Wide/shouldfail`'s 910 being 837 `Helpers.e` solves and 73 negatives; add
   the observed identity between the loop-draw and generative-rule rows.
9. **`E1-EXAMPLES.md` §7.2** — six more stdlib functions in the blast radius, `header#` promoted from
   guess to confirmed, and `.toMap` at three sites rather than one (§6).
10. **`tracker/LOOP-MODEL-PLAN.md`** — add the missing `E1` row (E2 and E3 both added theirs, and
    `brief-E-common.md` tells later stages to "append after the E1 row").

Recommended but not blocking, in order of value: a `Wide/Signatures.e` closing §7.3 and giving
`melt3` its missing call site; widening `SurveyPanel.scored` (§5.2); the two `sql-render.sh`
amendments (§4).

---

## 12. Wiring the orchestrator still owes

E1 did its own wiring, which is the point of the stage, and I checked all of it (§2). What is left
after this group commits:

* `core/examples/README.md` — three more rows in the "Grouped example sets" table (`Algebra/`,
  `Time/`, `Present/`) with their libraries; the section E1 added has room for them and needs no
  restructuring.
* `tracker/tools/corpus-run.sh` — the sibling groups in `files=(…)`, their `Helpers.e` hoist arms in
  both modes, and the header's "79 files" recount.
* `tracker/tools/looptrace-corpus.sh` — the sibling groups and their hoist arms in the `case`.
* `scalacheck-binding/.../TestSurfaceParsers.scala` — §3.4's floor (this is the only shared-file item
  that is a *correction* rather than an addition).
* `TestStatementExtents.scala` — the three "(271 files)" property titles are stale labels; de-number
  them.
* `tracker/LOOP-MODEL-PLAN.md` — the `E1` row.
* `tracker/TICKET-stdlib-findings.md` — §10 below.

---

## 13. Ticket recommendations (recommend, do not write)

E2's review already recommends creating `tracker/TICKET-stdlib-findings.md`. E1's findings belong in
the same file and two of them outrank everything E2 or E3 found.

**New `tracker/TICKET-stdlib-findings.md`:**

1. **`record#` / `scalaRecord#` / `scalaRecordIn#` return `MapView`s (Scala 2.13) — a live runtime
   panic.** `Lib.scala:988`, `:1007`, `:1012` need `.toMap`. Affected, all confirmed by grep and four
   of them by probe: `Relation.Pivot.pivot`, `pivotWithDefault`, `Relation.Predicate.all`,
   `Record.header`, `Record.anyRecordOrd`, `Relation.Sort.partialRecordOrd`,
   `Relation.nonEmptyRelation`, `Layout.Chart.srecKeys`, `Layout.Presentation`'s `extract#` path,
   and everything built on them (`Layout.Report.pivotTabular`, `Fulcrum/Legendary.e`). Reproduction:
   `scalaRecord# (record# { q = 1 })`, or force `core/examples/PivotTest.e`'s `pivotData`. **Add a
   test that forces a pivot** — laziness is why five years of `core/test` never saw this.
   *This is the highest-value item in the whole E-series.*
2. **`SqlEmitter.emitOver` is a stub on every emitter but MS SQL**, and it emits its TODO sentence
   *into the query text* — a silent wrong answer. Postgres and SQLite have had `OVER` for years.
3. **`SqlEmitter` emits a join whose right operand is a join without parentheses** (`:255-262`), which
   SQL-92 parsers re-associate correctly but SQLite's flat join grammar rejects. E2's
   `q_inv_moves.lite.sql` is the reproduction; `Wide/` does not trip it because its join trees are
   left-deep.
4. **`Scanner.dumpMem` is `sys.error("Don't know how to dump a mem.")`** (`Scanner.scala:33-35`) and
   `SqlScanner` does not override it; `SqlLoad` (the temp table `lookupLatest`/`nearestDate`
   materialise) has no emission case. Both are dumping limits, not execution limits, but dumping is
   the only execution this repository has.
5. **No `render` and no concrete `Writer`.** Documentation: `core/examples/Ai/*.e` headers and
   `Ai/README.md` tell the reader to type `render <report>`, which answers `undefined term`. Either
   ship a text writer or fix ten header blocks. (E3 reports this independently.)
6. **A field name colliding with a stdlib term fails at the record literal, not at the declaration**
   (`seq` from `Function`, `currency` from `Layout.Report`/`Format`/`Presentation`). Diagnostics.

**Additions to `TICKET-editor-and-solver-followups.md` item 4** (the blame-clause instability): the
`Wide/shouldfail/win01` pair, where both clauses can be checked against the program and the batch one
is the accurate one; the observation that the reported **field** can move too (`Inf02.a` →
`Inf02.b`); and the measurement that adding files to a batch command line deterministically reshuffles
other modules' diagnostics while the same command line is byte-stable across runs (§3.2). The
actionable consequence, which E2's review states and I confirm: **pin the field and the position,
never the sentence** — and the real fix is to report the reason for the CLASH, not the last
propagation to touch the label.

---

## 14. Renderings, REPL recipes, and the `melt3` residual

### 14.1 The renderings (G4) — 15 of 27, exactly as reported

`tracker/tools/sql-render.sh tracker/tools/wide-render-probe.e <scratch>/render`, one run:

```
15 executed with real rows:
  q_branch_trend 10   q_claims_decile 8   q_claims_fraud 8   q_claims_ratios 8
  q_leader_rank 9     q_leader_tile 9     q_leader_top 6     q_media_top 6
  q_share_one 8       q_share_two 8       q_survey_melt 24   q_trial_moving 10
  q_trial_running 10  q_ward_join 9       q_ward_pipeline 9
 4 "Don't know how to dump a mem.":   q_survey_mean, q_sales_group, q_sales_line, q_media_group
 2 "Emission not supported … SqlLoad": q_branch_spread, q_branch_usd
 6 Panic in scalaRecord#:              q_pivot_{quarter,line,survey,media,default,claims}
```

**Exactly the report's 15 / 4 / 2 / 6.** I spot-checked the *content*, not only the counts:
`q_leader_rank` comes back with 39 columns (the 38-column joined row plus `killRank`) and the same
nine rows in the same rank order the report prints; `q_trial_running` comes back with 28 columns and
the running balances −412000, −800500, −776500, −1227700 / 188000, 379400, 583300 / 41200, 80000,
132600, which is what the report prints and what the inline data implies. The route works and the
report's §6 tables are the tool's real output.

**N-7, revised.** The positional name↔SQL alignment (§4) held in this run, and I can now say exactly
when it would not: a REPL response only fails to start with `res` when the *expression does not
type-check* — a runtime panic still prints `resN : T = <error: …>` and consumes its name correctly.
So the trigger is a name in the `.in` file that the probe module does not define (a typo, or a
renamed binding), which would silently shift every following name. Narrower than I first thought,
still worth the one-line `assert k == len(names)`.

### 14.2 The header recipes all work — and one small trap

Driving the REPL exactly as the ten module headers say (`:load Wide/Helpers.e`, then
`:load Wide/<Module>.e`, then the `>>` expression each header prints):

```
Wide.Helpers 0.65   Leaderboard 0.90 → Relation (|coach, …|)
SalesLedger 1.50  → Mem (|q3, q2, customerName, q4, q1|)
TrialBalance 0.46 → Relation (|creditAmt, …|)     RevenueShare 0.50 → Relation (|segmentPct, …|)
SurveyPanel 0.23  → Relation (|questionScore, questionKey, waveId, respondentId|)
WardRoster 2.14   → Relation (|bankHolidayFlag, …|)  BranchDeposits 0.35 → Relation (|netFlowEur, …|)
MediaSpend 0.34   → Mem (|video, audio, monthName, social, search, display, campaignName|)
ClaimsExperience 1.52 → Relation (|lossRatioPct, …|)
```

**All ten recipes execute**, in one session with all ten modules loaded — `:load` resolves
`import Wide.Helpers` from the session even though the CLI cannot, and no printed expression hits an
ambiguous name. That is better than E2's group, where a name clash broke a printed recipe.

Two confirmations fall out of the same session: `render leaderboardReport` answers
`runtime error: <interactive>:1:1: error: undefined term` (finding 7.1, at runtime), and `:type
ledger` — a name `SalesLedger` and `TrialBalance` both define — answers the *same* `undefined term`
rather than an ambiguity message. The collision is harmless but the diagnostic for it is poor; one
sentence in `Wide/README.md` would save a reader the confusion (§5.3).

### 14.3 N-11 — the inferred `melt3` residual is 20 constraints, not 22

§7.6's headline is that annotating `melt3` turns a 22-constraint residual over 19 existentials into
2 over 1 — "an elevenfold reduction". I reproduced the experiment by putting the same body,
unannotated, in a scratch module (`melt3u`, same imports it needs) and reading its `.ei`:

```
melt3u : forall … (exists r21 rs ro r3 r4 r5 so rs1 t so1 ro1 rs2 t1 ro2 so2 e r22 t2 r23.
  t1 <- (rs1, so, ro2), r21 <- (rs, ro), r3 <- (c1, r2), t2 <- (rs2, so2, ro1),
  t <- (rs, so1, ro), r1 <- (r2, c1, rs2, ro1), RelationalComb rel, r23 <- (rs2, ro1),
  t1 <- (c1, e), r1 <- (r2, r, rs1, ro2), r21 <- (ro, rs), r1 <- (r, c1, ro, rs),
  r22 <- (rs1, ro2), c <- (rs2, so2), d <- (a, e), t <- (r2, e), c <- (rs1, so),
  r4 <- (r, r2), t2 <- (r, e), r5 <- (c1, r), c <- (rs, so1)) => …
```

**20 partition constraints over 19 existentials**, not 22 over 19. The 19 existentials match exactly;
the two missing constraints are, comparing the two lists, the *duplicated-up-to-argument-order* pairs
`r22 <- (ro2, rs2)` / `r22 <- (rs2, ro2)` and `r23 <- (rs1, ro1)` / `r23 <- (ro1, rs1)` — E1's
published list carries both members of each pair, mine carries one. That is the residual
non-canonicality D1's review documented (published constraint lists print in `Set` = hash = id order
and are not canonicalised), so **the count is a property of where the definition sits, not of the
body**: 22/2 = "elevenfold" in `Helpers.e`, 20/2 = "tenfold" in mine.

The lesson survives intact and is arguably sharpened — a hand-written signature is not merely smaller
but *stable*, where the inferred one is not — but §7.6's "22" should be given as "20–22, depending on
the module the definition sits in", and this is fresh evidence for the R1 memo's canonical-residual
proposal (`tracker/ROSE-COMPARISON.md`).

---

## 15. Every number of mine that differs from the report's

The list is short, which is the main thing to say about `E1-EXAMPLES.md`. **The differential, the
census (all three columns, every cell), the interface counts (85 across 19 of 24, per helper, nine
reports at 0), the rendering split (15 / 4 / 2 / 6) and the batch verdicts (33 / 46 / 0 / 79) all
reproduce exactly.** What differs:

| # | report | mine | reading |
|---|---|---|---|
| 1 | inferred `melt3`: **22** constraints over 19 existentials | **20** over 19 | N-11: the published list is not canonical; two duplicated-up-to-argument-order constraints survive in one module and not the other. "Elevenfold" is 10–11× |
| 2 | bundling "still costs **3–4×**" | **1.2×** controlled (1.27 s vs 1.07 s); ~2× on E1's own small module | N-4: the 3–4× comes from comparing two whole modules that differ in four ways; the controlled A/B/C says 1.2× |
| 3 | form C 1.30 / 1.51 s; form A 1.46 / 1.05 s | C **1.28 / 1.27**, A **1.06 / 1.08**, B **1.09 / 1.06** | same conclusion (C finishes), tighter numbers on a quieter box |
| 4 | negatives rejected in "0.05 s (both sweeps)" | **0.06 / 0.09 / 0.14 s** (`Unable to load module … (t)`) | rounding; `win02` is 2–3× the other two |
| 5 | `SalesLedger` 1.17 / 1.18 s | **1.30 s** | contention; inside the spread of the other modules |
| 6 | batch 29 s | **32 s** (old script 28 s) | contention |
| 7 | "the corpus went 271 → **315**" | **333** now (161 stdlib + 172 examples) | the tree moved under E1; the derived count is why the property still passes |
| 8 | `sbt core/test` 913/914 with a transient third failure from a sibling stage | the three sweeps alone, on the settled tree: **20 properties, 0 failed, all proved** (96 s) | E1's gate was measured mid-race; it is clean now, including the repaired 2.3a property |
| 9 | `Wide/shouldfail` census: 910 solves | **910**, of which **837 are `Helpers.e`** and **73 the negatives** | presentational, §9.1 |
| 10 | "**47×** the per-file sweep" (of the 29 s batch) | 1,376 / 32 ≈ 43× *faster* | phrasing: the batch is 47× faster, not 47× the sweep |
| 11 | §3b: 7 of 79 files differ per-file vs batch | reproduced; **and 9 more differ old-script-batch vs new-script-batch** | N-2, §3.2 — a comparison the report did not make |

Nothing in this list changes a conclusion except items 1 and 2, and item 2 changes only a multiplier
in a piece of advice that stays correct.

---

## 16. Bottom line

`E1-EXAMPLES.md` is a trustworthy report. I re-ran the differential (170,619 new segments plus an
83,942-segment control, all 0/0/0), the whole census (three columns, twenty-odd cells, not one
different), the interface sweep (85 partitions, per helper, and byte-identical across two JVMs), the
batch and per-file loads, the three negatives, the fifteen renderings and the RUnion re-measurement,
and the only substantive corrections are a residual count that is not stable across modules and a
cost multiplier taken from an uncontrolled comparison.

The group is a real addition. It closes two genuine holes in the corpus (`Relation.Windowed` had
**no** example caller; `Relation.Pivot` had one toy), it is the first example code in the tree whose
rendered output can be checked arithmetically against inline data, and the census claim it makes —
**bigger, not deeper**: 21 variables, 14 partitions, 46 labels, 249 steps, 77 draws, `Resolution` 62
in one solve, eight solves at depth 3, and still nothing within two orders of magnitude of the
20,000-draw budget — is exactly right and exactly as stated.

The shared-file edits are, with one exception, correct and minimal, and the exception
(`TestSurfaceParsers`) is a right idea with a one-line hole in it. The SQL execution route is the
most useful piece of tooling any E-stage has produced and should be kept, and two other groups are
already depending on it.

And the stage found a **live runtime bug that makes `Relation.Pivot.pivot`, `Relation.Predicate.all`,
`Record.header`, the record `Ord` and five other standard-library functions panic when forced** — in a
tree where the only pivot example never forced its own result. That is worth more than the ten
modules, and it should be the next fix stage, with the `.toMap` at three sites (not one) and a test
that forces a pivot.

**FIX-THEN-ADVANCE**: apply §11 — an hour's work, all of it prose except the one test line — then
commit the group and the tooling.
