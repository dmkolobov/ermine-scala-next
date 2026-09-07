# F1-REVIEW — the MapView panic (A1) and the piped-console loop (A2), re-run from scratch

Reviewer pass over stage F1 (brief `tracker/loopmodel/briefs/brief-F1.md`, report `tracker/loopmodel/F1-FIXES.md`),
branch `scala3-migration`, base `5ab6e7e`, changes uncommitted.

**Nothing below is copied from the F1 report.** Every number is from my own runs. The pre-fix side is a fresh
`git worktree` at `5ab6e7e` (full rebuild from clean, `BUILD_RC=0`, 153 core sources) with
`TestRecordPrims.scala` copied in, so the new test runs on *both* compilers; the post-fix side is the working
tree as the implementer left it. JDK 21.0.12.1, `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM
at a time, `-Dermine.useInterface=false` throughout, `.ei` swept after every phase (final sweep: 0 in both
trees). `tracker/lean/` untouched, no commits; the only repository file I wrote is this one. The worktree has
been removed. Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-F1/`.

## VERDICT: **ADVANCE (commit)**

Both bugs are real, both fixes are minimal and correct, both are covered by tests that fail without them (I
measured the negative control myself), and every gate reproduces. Three of my numbers come out *better* than
the report's and one comes out different in a way that is bookkeeping only. The `J-` items below are ticket
material and documentation corrections; none of them is a reason to hold the commit.

**Negative control (the thing the report most needed checked): CONFIRMED.** On a clean `5ab6e7e` build with
`TestRecordPrims.scala` dropped in unchanged, `sbt core/testOnly …TestRecordPrims` gives

    Failed: Total 8, Failed 3, Errors 5, Passed 0

— 8 of 8 fail without the `Lib.scala` fix. Each failure names the defect (`MapView(<not computed>)`), and one
is a `ClassCastException: scala.collection.MapView$MapValues cannot be cast to
scala.collection.immutable.Map` — i.e. the test bites on the mechanism, not only on the symptom. The tests are
real tests.

**Consumers the fix missed: none on the `record#` path** (I re-grepped it end to end; §3). But the *same
defect family* has three more live sites elsewhere in the tree, which I confirmed by running them — see
**J-3**, the one finding worth acting on.

---

## 1. Reproductions

### 1.1 A1 — the primitives (one REPL session per side)

| forced expression | BEFORE (`5ab6e7e`) | AFTER |
|---|---|---|
| `record# { w = 1, q = 2 }` | `res0 : Record# = MapView(<not computed>)` | `Map(q -> 2, w -> 1)` |
| `scalaRecord# (record# { q = 1 })` | `Panic: unexpected runtime value in Native.Record.scalaRecord# - MapView(<not computed>)` | `Map(q -> 1)` |
| `header# (record# { w4 = 1 })` | `Panic: … Record.header# - MapView(<not computed>)` | `List((w4,IntT(false)))` |
| `header { w4 = 1 }` (`Record.header`) | `(Row <error: Panic: … Record.header# - MapView…>)` | `(Row [("w4",IntT(false))])` |
| `all { ee = 1, ff = 2 }` (`Relation.Predicate.all`) | `Panic: … scalaRecord# - MapView(<not computed>)` | `And(Eq(ColumnValue(ff,IntT(false)),OpLiteral(2)),Eq(ColumnValue(ee,IntT(false)),OpLiteral(1)))` |

All four of the report's §2.1 rows reproduce, plus `header#` directly.

### 1.2 A1 — the seven E-report bindings, values checked against the modules

All seven panic before and evaluate after. I checked the VALUES, not just the absence of a panic:

| binding | AFTER, and why the value is right |
|---|---|
| `PivotTest.pivotData` / `pivotData2` | `Success(Map(Issue, MarketCap, Price, Sector -> StringT(0,false)))` — `PivotTest.e`'s `f3` pivots `Sector`, `Price`, `MarketCap` and `Issue` passes through: 4 columns, correct |
| `Wide.MediaSpend.spendByChannel` / `…Filled` | `Success(HashMap(campaignName, monthName -> StringT; social, video, audio, display, search -> DoubleT))` — matches the declared `Mem (\|video, audio, monthName, social, search, display, campaignName\|)` |
| `Present.FulcrumPanel.bothHalves` | `Fulcrum ["periodLabel"] ["energyMwh"×4,"availPct"×2] [(Map(periodLabel -> Q4),("q4Value",…)), (Q3,q3Value), (Q2,q2Value), (Q1,q1Value), (Q2,q2Avail), (Q1,q1Avail)]` — the six raw `MapView(<not computed>)` are now six real `Map`s and **each label matches its own column** (Q4↔q4Value … Q1↔q1Avail), against `FulcrumPanel.e:272-277`'s `{periodLabel = "Q1"}` etc. |
| `Algebra.SoftSchema.pivoted` / `pivotedTyped` | `Success(HashMap(assetId -> IntT; firmware, lastFault, tempC, hoursRun, voltageV -> StringT))` — six columns, matching `pivotedTyped`'s declared `Mem (\|assetId, voltageV, tempC, hoursRun, firmware, lastFault\|)`. (The numeric-looking columns are `StringT` because `readingValue` is a String column in that soft-schema module — the module's shape, not the fix's doing.) |

### 1.3 A2 — the piped inputs (20 s cap)

| input | BEFORE | AFTER |
|---|---|---|
| `printf 'staircase\n'` | **rc=124**, 2,471 `\|>` prompts | **rc=0**, 0 prompts, 7.9 s |
| `printf '"complete"\n'` | **rc=124**, 3,040 prompts | **rc=0**, 0 prompts, 7.6 s |
| `printf 'f x = case x of\n'` (a REAL keyword at EOF) | **rc=124**, 3,031 prompts | **rc=0**, 1 prompt, 8.1 s |
| `printf 'staircas\n'` | rc=0, 0 | rc=0, 0 — **transcript byte-identical** |
| `printf 'f x = case x of\n  1 -> 2\n\nf 1\n'` | rc=0, 2 | **byte-identical** |
| `printf '(x -> case x of\n  1 -> 2\n  _ -> 0) 1\n\n'` | rc=0, 3, `res0 : Int = 2` | **byte-identical** |
| `printf '(let y = 41 in y + 1)\n\n'` | rc=0, 1, `res0 : Int = 42` | **byte-identical** |
| `printf 'staircase\n\n'` | rc=0, 1 prompt | rc=0, **0** prompts — the one intended behaviour change, as documented |

Byte-comparison done from `Loaded N modules` to EOF: the four continuation controls are IDENTICAL, and
`staircase_blank`'s delta is exactly the two lines the report predicts (the `|>` disappears; the blank line
becomes an empty command). Both halves of the fix are load-bearing and the report attributes them correctly:
the token change alone cannot rescue `f x = case x of`, and the null-as-EOF change alone cannot stop
`staircase` opening a continuation.

**My prompt counts differ from the report's** (2,471/3,040/3,031 vs its 2,411/2,378/2,493). They are
iteration counts inside a 20 s wall-clock cap, so they are machine- and run-dependent by construction — see
**J-2** about quoting one in the ticket.

---

## 2. Gates — all re-run

| gate | measured here | verdict |
|---|---|---|
| `core/test` | `Total 922, Failed 1, Errors 0, Passed 921`; the one failure is the known `Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.` (913 + 8 new = 921) | PASS |
| the 8 new properties, pre-fix | `Total 8, Failed 3, Errors 5, Passed 0` | PASS |
| `TestLoopTrace` | `714 solves; 714 segments; 714 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0; rejected=36 fuel=0`; controls live at 46/714 (id base +1) and 58/714 (`--flags=nongen`) | PASS |
| row trace, `Wide` + `Algebra` | `Wide` **566,155** records, `Algebra` **422,039** — identical counts on both builds and across runs. Normalized for the repo path and with the `rsound` elapsed column masked: **before-vs-after = 0 differing lines on both groups** | PASS |
| …and the elapsed column moves on ONE build | two runs of the *post-fix* build differ on 18,248 (`Wide`) / 15,800 (`Algebra`) lines, **all of them `rsound`**, and masking that single column takes both to 0 | CONFIRMED |
| `corpus-run.sh --batch`, 151 files | **82 LOADED, 69 REJECTED, 0 UNKNOWN** on all **six** runs (3 pre-fix, 3 post-fix) | PASS |
| corpus output diff | after1-vs-after2 **0 of 151**; before1-vs-before2 **0 of 151**; before1-vs-after1 **2 of 151, and both differences are the absolute path of my worktree** inside a stdlib blame location — substantively **0 of 151** (better than the report's "one file's message differs") | PASS |
| `sql-render.sh` | `diff -rq` **empty** on both `sql/` and `out/` — all 15 queries and 15 result tables byte-identical | PASS |
| `repl-smoke.sh` | rc=0, 5 of 5 PASS, **47 checks** (aliasing 2, pipedeof 12, relations 6, scoping 4, smoke 23) | PASS |
| `lsp-smoke.sh` | rc=0, `PASS lsp (98 checks)` | PASS |
| `.ei` hygiene | 0 under `core/examples` and `core/src/main/resources/modules` in both trees | PASS |

---

## 3. The diffs, read line by line

### `session/Lib.scala` (+12 −3) — the three `.toMap`s are minimal and correct

`rec` (`Record#`) has exactly four consumers, and all four demand a real `Map`:
`scalaRecord#` (`:1016`, `case Prim(t: Map[String, Runtime])`), `header#` (`:1026`, same pattern),
`unsafeRecordIn#` (`:1001`, `p.asInstanceOf[Map[String,Runtime]]` — which throws `ClassCastException` on a
view, as the E1 review predicted), and `Rec`-side arithmetic. `scalaRec` (`ScalaRecord#`) has one producer
(`scalaRecord#`) and one Ermine-side consumer that reads it back (`scalaRecordIn#`), plus `pivot#`'s
`km.extract[List[(Record, …)]]`. So the *producers* are `record#`, `scalaRecord#` and `scalaRecordIn#` — the
three lines changed — and nothing else needs one. `header#` already had its own `.toMap`; its panic was
`record#`'s view arriving, and it is fixed by the first line.

I re-grepped `mapValues` and `filterKeys` across `core/src/main`, `parsers`, `machines` and `scalaz-compat`.
**The report's §5 table is accurate, including its line numbers** (`:309-322` `Native.Map`, `:472/474/476`
`Field.cons`/`!`/`\`, `:572-583` record restrict/remove, `:821` `relation#`, `:934` scanner rows,
`Runtime.scala:163` `Rec.nf`, `package.scala:34` `recordHeader` — every one already strict or Map-in/Map-out).
I checked the stdlib and foreign-binding side too: `Native/Record.e`'s only foreign binding is
`anyRecordOrd## = com.clarifi.reporting.package.RecordOrder`, a derived `Order[Record]` with no views, and
every `ScalaRecord#` foreign method (`Relation/Predicate.e:36`, `Layout/Presentation.e:29`,
`Relation/Sort.e:133`, `Layout/Chart/Unsafe.e`, `Layout/Report.e:1588,1597`) consumes rather than produces.

One correction to the report's reasoning, not its conclusion: it explains `Layout/Report.e:622`'s
`lmap unsafeRecordIn#` as "receives a scanner row". The `Record#` values on that path actually come from the
writer hook `scanRelationDMTL`, and what makes them safe is the `.toMap` already present at
`core/src/main/scala/com/clarifi/reporting/writers/Writer.scala:253`. Right answer, wrong provenance.

**Did anything rely on the laziness?** No, and it could not have: pre-fix, *every* path out of `record#`
panicked or threw, so no working behaviour existed to regress. On performance the change is neutral-to-better
— the `MapView` re-ran `_.whnf` on every access where `.toMap` runs it once, and `Runtime.Thunk` memoizes
anyway (`Runtime.scala:195-215`), so neither form re-does real work. On the report's A7 strictness note: it is
correct. `Prim.apply(p: => Any)` (`Runtime.scala:154`) forces inside a `try` and converts a `Throwable` to
`Bottom`, so a record with a throwing field now Bottoms at `record#`. The *only* constructible way to observe
the difference is to force `record# r` to WHNF and never inspect it, with a bottom field — nothing in the
stdlib or the corpus does that, because all six consumers inspect immediately.

### `session/Console.scala` (+22 −3) — the token test is right for Ermine's lexer

`(?<![A-Za-z0-9_'#])(case|let|where)(?![A-Za-z0-9_'#])`. Ermine's identifier tail is
`ParsingUtil.scala:337`, `tailChar = c.isLetter || c.isDigit || c == '_' || c == '#' || c == '\''` — so the
boundary class is the right set. I tested it against the real corpus rather than against invented examples:
I extracted every identifier-shaped token from the 129 stdlib modules and the 151 example files, took the
**57** that contain `case`/`let`/`where` as a substring (`anywhere`, `cases`, `complete`, `delete`, `letter`,
`letM`, `lowercase`, `palette`, `showcase`, `elsewhere`, `everywhere`, `nowhere`, `incomplete`, `obsolete`,
`doubleton`, `pallet`, `Pellet`, …) and confirmed **none of the 57 matches the new regex**, while all nine
genuine-keyword controls (`case`, `let`, `where`, `f x = case x of`, `(let y = 41 in y + 1)`, `x where y`,
`}where`, `$let`, `case(x)of`) do. Qualified names are not an issue: the three are keywords
(`parsing/package.scala:29`), so `M.case` cannot exist. The affix convention this codebase uses (`let_Foo`,
`x_let`, `single_Brace`) is excluded by `_` on the correct side.

`blank = (last == null) || (last == "")` ends the continuation at EOF **without losing the command**: `input`
is what was read and is then parsed — visible in `pipedeof.expected`, where `f x = case x of` produces its
parse error rather than vanishing. The other five `readLine` sites are null-safe as claimed, and I checked
each: `Console.scala:146` is the wrapper that mints the `null`; `:744`'s `repl` loop guards with
`line != null`; `:323` `:paste` hands its text to `other` and inherits the fix; `lsp/Rpc.scala:315` returns
`Option[String]` and both call sites (`:255`, `:266`) test it; `machines/…/Example.scala:35` wraps in
`Option`. The keyword-in-a-string case is a deliberate, documented, non-regressing wart — see **J-5**.

### `tracker/tools/repl-smoke.sh` (+16 −2) and the golden

The timeout and exit-code check are the right shape (`rc` is captured from `timeout`, 124 is named, a failing
input `continue`s instead of being diffed). `pipedeof.expected`'s 12 lines are fully deterministic — they pin
the `|>` prompt count positionally, and nothing in them depends on the machine or the module count. The 180 s
default is an ~18x margin over the 10 s these inputs actually take here, and is overridable. See **J-9** for
two cosmetic nits.

---

## 4. The two things that moved — both confirmed as stated

**(a) The six `q_pivot_*` probes.** Confirmed both by running and by reading. On BOTH builds
`q_survey_mean`, `q_sales_group`, `q_sales_line` and `q_media_group` print `<error: Don't know how to dump a
mem.>`; pre-fix the six `q_pivot_*` printed the `scalaRecord#` panic and post-fix they print that same
message. The wall is `Scanner.scala:33-35`, a base-class `sys.error`, and `SqlScanner` overrides only
`dumpRel` (`:281`) — so **every** `Mem`-valued probe hits it and a pivot still renders no SQL, for a reason
unrelated to A1. No `.sql` or `.txt` changed.

**(b) `Present/shouldfail/chart01`'s clause.** My result is *cleaner* than the report's: in all **six** of my
151-file batches — three pre-fix and three post-fix — the clause was `a part contains it but the whole does
not`, so on this machine it does not move with the fix at all. The implementer's pre-fix runs produced
`whole, whole, part` from one binary. Taken together: the same pre-fix binary yields both clauses across
machines and runs, the two of us get different modal clauses out of the identical pre-fix build, and the
verdict (`82/69/0`) never moves. The observed clause is not caused by F1. Agreed with the report's
conclusion, on independent evidence — but see **J-6** and **J-7** about how it is written down.

---

## 5. Findings

### J-1 — the report's negative-control breakdown is wrong (CONFIRMED, cosmetic)

F1-FIXES §4 says "**8 of 8 fail** … (4 falsified, 4 raised on `extract` of a `Bottom`)". Measured:
`Failed: Total 8, Failed 3, Errors 5, Passed 0` — **3 falsified, 5 raised**, and one of the five is a
`ClassCastException`, not a `Death` on a `Bottom`. The headline (8 of 8) is right; the split is not.
Input: `sbt -batch 'core/testOnly com.clarifi.reporting.TestRecordPrims'` on a clean `5ab6e7e` worktree with
`TestRecordPrims.scala` copied in.

### J-2 — the ticket quotes a prompt count that will never reproduce (CONFIRMED, prose)

A2's new ticket text states "`printf 'f x = case x of\n' | bin/ermine`: 2,493 prompts and rc=124 before, 1
prompt and rc=0 after". I measure 3,031. The count is how many loop iterations fit inside the 20 s cap, so it
is a property of the machine, not of the bug. In a durable ticket, prefer "thousands of `|>` prompts, still
running when killed at 20 s (rc=124)"; the `1 prompt and rc=0 after` half *is* stable and worth keeping.
Same applies to §2.3's 2,411 / 2,378 (I get 2,471 / 3,040).

### J-3 — three more escaped-2.13-view sites, same family, on the pivot and join paths (CONFIRMED, ticket item — the one worth acting on)

`tracker/03-core-progress.md` records the migration policy: `.toMap` was applied "**only** at the ~20 sites
the compiler rejected — sites that stay generic keep the old lazy behaviour". A1 is one residue of that
policy: `Prim(…)` takes `Any`, so the compiler could not reject it. The *other* place the compiler cannot
reject a view is `==` and hashing — and three such sites are still live. I compiled a probe **inside
`package com.clarifi.reporting.relational` against the project's own classpath** and ran it:

```
== SqlScanner.scala:644 `prime` ==                     (val kr = r filterKeys pKey ; if (kr == k) …)
  kr runtime class : scala.collection.MapView$FilterKeys
  kr == k       ==>  false          (kr.toMap == k  ==>  true)
  bootstrap = Map(c -> 999)         (999 is the DEFAULT; the real value 42 was dropped)

== SqlScanner.scala:708 `hashJoin` ==                  (Tee.hashJoin(_ filterKeys jk, _ filterKeys jk))
  key runtime class            : scala.collection.MapView$FilterKeys
  Map[Record,_].getOrElse(key) : NO MATCH             (with .toMap: JOINED)

== relational/package.scala:67 `sorting` chunk predicate ==
  (t1 filterKeys chunk) == (t2 filterKeys chunk) : false     (with .toMap: true)
```

So: the in-memory pivot gives every pivoted column its **default** on the first row of each pivot group;
`SqlScanner`'s hash join matches nothing (`Tee.hashJoin`, `machines/…/Tee.scala:72`, builds a `Map[K, …]` and
looks up with `getOrElse`); and `sorting`'s chunk grouping never groups, so the secondary sort inside a chunk
never happens. The in-tree contrast is stark and makes the diagnosis certain: **the same calls are written
correctly a few lines away** — `SqlScanner.scala:629/630` and `:538` use `.toMap`, and
`Optimizer.scala:277` writes the very same call as
`Tee.hashJoin[Record, Record, Record]((r: Record) => (r filterKeys jk).toMap, …)`.

These are **pre-existing, not caused by F1, and out of F1's scope** — no gate moves, because the corpus cannot
reach the in-memory execution path today (no writer is wired, and every pivot stops at `dumpMem`). But they
are the same defect family on the very feature F1 just unblocked, so the first program that actually *runs* a
pivot or a hash join will meet them. Recommend a ticket item (an "A1b"): add `.toMap` at those three sites,
with a test that runs a pivot through the scanner rather than only forcing its plan.

### J-4 — the token boundary is ASCII where Ermine's is Unicode (PLAUSIBLE, cosmetic)

`[A-Za-z0-9_'#]` vs `tailChar`'s `c.isLetter || c.isDigit || …` (Unicode) and `identStart = satisfy(_.isLetter)`.
A Unicode identifier abutting a keyword (`λlet`, `letλ`) would falsely open a continuation. I checked: **zero
occurrences** across the 129 stdlib modules and 151 corpus files, and the consequence is one extra `|>` prompt
that now always terminates — so this is cosmetic, not a defect. `[\p{L}\p{N}_'#]` would close it if the file
is ever touched again.

### J-5 — a keyword inside a string literal still swallows the next piped line (CONFIRMED, no regression, worth naming)

`"where to?"` matches the token test, as the code comment says. Not a regression (the old `contains` matched
it too) and no longer unbounded. What the report does not spell out is the consequence for a *piped script*:
the next line is appended into the same command, so a `.in` file containing `printLn "where am I"` would
silently mis-parse the line after it. No `.in` in the tree does this today (I checked every
`tracker/repl-tests/*.in` and `tracker/tools/*.in`; the only hits are real keywords inside `:type`). Worth one
sentence in the ticket so the next person writing a REPL script knows the rule.

### J-6 — B6's ticket wording is narrower than what was measured (CONFIRMED, prose)

B6 says the clause "varies with load order", which implies determinism once the order is fixed. The 151-file
batch has a fixed order and still yields different clauses across runs of one binary (the parallel batch
loader). B6 should gain "…and, under the parallel batch loader, run to run on one binary".

### J-7 — `chart01`'s "EXPECTED (verbatim)" docblock is only true per-file (CONFIRMED, doc)

`core/examples/Present/shouldfail/chart01_series_not_in_relation.e:14-18` states
`EXPECTED (verbatim): … the whole contains it but no part does`. That holds in the deterministic per-file mode
on both builds; in a 151-file batch either clause can appear (mine printed the other one six times out of
six). One line in the fixture — "in a batch run the other clause of the same refutation may print; see B6" —
would stop a future reader reading it as a regression.

### J-8 — the brief's file paths are wrong; the implementer followed the repo convention (CONFIRMED, no action)

The brief names `core/src/main/scala/com/clarifi/reporting/ermine/Lib.scala` and
`core/src/test/.../TestRecordPrims.scala`. The real files are `…/ermine/session/Lib.scala` and
`scalacheck-binding/src/main/scala/TestRecordPrims.scala` — which is where all sixteen other `Test*` property
files live, and `build.sbt:90` puts that directory on `Test/unmanagedSourceDirectories`. The implementer was
right; only the brief was wrong. Noted so the next brief copies the correct paths.

### J-9 — two cosmetic nits in `repl-smoke.sh` (CONFIRMED, cosmetic)

The raw transcript `/tmp/repl-smoke-<name>.raw` is left behind on the PASS path (five files per run, alongside
the pre-existing `.diff` files) — one `rm -f` on success would tidy it. And `timeout` has no `-k`, so a JVM
that ignored `SIGTERM` would linger; JVMs do not, so this is theoretical. Neither can flake a check.

### J-10 — the row trace has two comparison traps the report's own advice walks into (CONFIRMED, tooling note)

F1-FIXES §6 tells the next person to "compare with column 8 of the `rsound` lines masked" and calls the
elapsed field "the `rsound ok` records' LAST field". Both are off, and I hit it:

* `RowTrace.log` appends a **thread id** (`t0`) after the elapsed microseconds, so the elapsed is the
  **second-to-last** field, not the last. Masking `$NF` leaves all 18,248 `Wide` lines still differing;
  masking `$(NF-1)` takes them to 0.
* The field appears on **every** `rsound` kind (`trySolveOn`, `mkSimplified-extinct`, …), not only on `ok`.
* Records embed the **absolute repository path**, so any A/B taken across two checkouts or worktrees needs a
  path normalization first (this also produced the only two "differing" corpus files in my run). The
  implementer used `git stash` in one directory and so never met it.

The recipe that actually works, for whoever asserts this next:

```sh
norm() { sed 's|/home/…/ermine-scala[a-zA-Z0-9._-]*/|/REPO/|g' "$1" |
         awk -F'\t' 'BEGIN{OFS="\t"} $1=="rsound" && NF>=3 {$(NF-1)="ELAPSED"} {print}'; }
diff <(norm a.tsv) <(norm b.tsv)          # 0 lines, both groups, before vs after
```

---

## 6. What I did not find

* No consumer of `record#` / `scalaRecord#` / `scalaRecordIn#` / `header#` is left unfixed.
* Nothing solver-visible moved: `TestLoopTrace` 714/714, and 988,194 loop-trace records over two corpus
  groups are byte-identical between the builds. Neither changed file is on an inference path —
  `Lib.scala`'s three sites are runtime primitives that run only when a value is forced (which is precisely
  why A1 survived: `:load` type-checks without evaluating), and `Console.scala` decides how many input lines
  make one command.
* `tracker/ROW-CONSTRAINT-STATE.md` correctly went untouched.
* The ticket's A1/A2 entries are otherwise accurate, cite the right post-fix line numbers
  (`Lib.scala:997`, `:1016`, `:1021`), and both leave `<commit>` for the orchestrator to fill, as the brief
  asked.
