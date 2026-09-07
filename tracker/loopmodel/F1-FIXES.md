# F1 — two runtime fixes from the corpus programme: the MapView panic (A1) and the piped-console loop (A2)

Stage F1 of the loop-model programme (`tracker/loopmodel/briefs/brief-F1.md`).
Branch `scala3-migration`, base commit **`5ab6e7e`** (S3 plus its handoff; the five example groups and the
row-solver defaults are in).  Tickets: `tracker/TICKET-stdlib-findings.md` **A1** and **A2**.
Findings came from E1 §7.2, E1-REVIEW §6, E4 §4.6 / §4.7, E4-REVIEW F5 / M-5, E5 §4.4.

Toolchain: JDK 21.0.12.1, `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time.
Every REPL reproduction ran with `-Dermine.useInterface=false`; the sweeps delete `.ei` before each run,
and a final `find core/examples core/src/main/resources/modules -name '*.ei' -delete` printed nothing.
No commits.  `tracker/lean/` untouched.

**OUTCOME: GREEN** — both bugs fixed, both with tests, every gate met.  Two things moved that are not
regressions and are stated in full in §4: the six `q_pivot_*` `sql-render` probes moved from the panic
to the pre-existing "don't know how to dump a mem" wall, and one `shouldfail/` module printed the other
clause of the same refutation — ticket B6, MEASURED here to be nondeterministic run to run on the
PRE-FIX build alone (18 runs, §4).

**Files changed**

| file | change |
|---|---|
| `core/src/main/scala/…/session/Lib.scala` | +12 −3 — the three `.toMap`s and a comment (A1) |
| `core/src/main/scala/…/session/Console.scala` | +22 −3 — `opensLayout` and null-as-EOF (A2) |
| `scalacheck-binding/src/main/scala/TestRecordPrims.scala` | NEW, 181 lines — 8 `core/test` properties that FORCE the values (A1) |
| `tracker/repl-tests/pipedeof.in` / `.expected` | NEW — 12 smoke checks for the piped inputs and the continuations (A2) |
| `tracker/tools/repl-smoke.sh` | +16 −2 — a timeout and an exit-code check, so a hang fails instead of hanging |
| `tracker/TICKET-stdlib-findings.md` | A1 and A2 marked fixed (the commit hash is left as `<commit>` for the orchestrator) |

---

## 1. What was wrong

### A1 — `record#` published a Scala 2.13 `MapView`

`Native.Record.record#` (`Lib.scala:988` before the fix) answered `Prim(m.mapValues(_.whnf))`.  Since
2.13 `Map#mapValues` returns a **lazy `MapView`, which is not a `Map`**, so the value published at type
`Record#` never matched any consumer's `case Prim(_: Map[String,Runtime])` and `whnfMatch` fell through
to its panic.  Two more sites had the same defect on their own results — `scalaRecord#` (`:1007`) and
`scalaRecordIn#` (`:1012`) — which is why the fix is three `.toMap`s and not one (E1-REVIEW §6.3).
Nothing caught it because Ermine is lazy, `:load` type-checks without evaluating, and nothing in
`core/test` ever forced a pivot.  `core/examples/PivotTest.e`'s `pivotData` had been unevaluatable for
years.

### A2 — `Console.other` could not terminate on a piped line

Two independent defects in one loop (`Console.scala:623–628` before the fix):

1. the continuation opened whenever the line merely **CONTAINED the substring** `case`, `let` or
   `where` — so `staircase`, `"complete"` (comp-**let**-e), `palette`, `delete`, `showcase`,
   `elsewhere` all opened one;
2. `readLine` answers **`null`** at end of input (`:146`; jline 3 throws `EndOfFileException` and the
   wrapper turns it into `null`), and `null == ""` is false in Scala, so `blank` never flipped: each
   pass appended `"\n" + null` and re-ran `balanced()` (a walk of the whole string) plus three
   `contains` scans over an ever-growing string.  **Unbounded**, not merely slow.

**Which change fixes which symptom** (both kept, they are independent):

* the **token** change fixes `staircase` and `"complete"`: no continuation is opened at all, so those
  lines behave exactly like the `staircas` control (0 prompts, exit 0).  It does nothing for a line
  with a real keyword.
* the **null-as-EOF** change fixes the unboundedness: a line that legitimately opens a continuation
  and then meets EOF now ends it and processes what was read.  Measured on
  `printf 'f x = case x of\n' | bin/ermine` — a genuine `case` — which the token change cannot help:
  **rc=124 with 2,493 prompts before, rc=0 with 1 prompt after**.  The same change also ends the
  `balanced(input) == Unbalanced` and `needMoar` loops at EOF (an unclosed `(`, a line ending in `=`).

---

## 2. Reproductions, before and after

One JVM at a time; ~13 s of every elapsed time below is the 129-module stdlib boot.

### 2.1 A1 — the primitives (probe modules in the scratch dir, one REPL session each side)

| forced expression | BEFORE (`5ab6e7e`) | AFTER |
|---|---|---|
| `record# { w = 1, q = 2 }` | `res0 : Record# = MapView(<not computed>)` | `res0 : Record# = Map(q -> 2, w -> 1)` |
| `scalaRecord# (record# { q = 1 })` | `res1 : ScalaRecord# = <error: Panic: unexpected runtime value in Native.Record.scalaRecord# - MapView(<not computed>)>` | `res1 : ScalaRecord# = Map(q -> 1)` |
| `all { q = 1 }` (`Relation.Predicate.all`) | `res2 : Predicate (\|q\|) = <error: Panic: … Native.Record.scalaRecord# - MapView(<not computed>)>` | `res2 : Predicate (\|q\|) = Eq(ColumnValue(q,IntT(false)),OpLiteral(1))` |
| `header { w4 = 1 }` (`Record.header`) | `res0 : Row (\|w4\|) = (Row <error: Panic: unexpected runtime value in Record.header# - MapView(<not computed>)>)` | `res0 : Row (\|w4\|) = (Row [("w4",IntT(false))])` |

### 2.2 A1 — every module the E-reports listed as panicking when forced

| module / binding | BEFORE | AFTER |
|---|---|---|
| `PivotTest.pivotData` | `<error: Panic: … scalaRecord# - MapView(<not computed>)>` | `<relation with Success(Map(Issue -> StringT(0,false), MarketCap -> StringT(0,false), Price -> StringT(0,false), Sector -> StringT(0,false)))>` |
| `PivotTest.pivotData2` | same panic | the same header |
| `Wide/MediaSpend.spendByChannel` | same panic | `<relation with Success(HashMap(social -> DoubleT(false), video -> …, campaignName -> StringT(0,false), audio -> …, monthName -> …, display -> …, search -> …))>` |
| `Wide/MediaSpend.spendByChannelFilled` | same panic | the same header |
| `Present/FulcrumPanel.bothHalves` | `<error: Panic: … Record.header# - MapView(<not computed>)>` in place of the fulcrum's key list, and **six raw `MapView(<not computed>)`** values inside it | `(MF (LF (Fulcrum ["periodLabel"] [...] [(Map(periodLabel -> Q4),("q4Value",…)), (Map(periodLabel -> Q3),…), …]) (Legend …)))` — the key rows are real `Map`s |
| `Algebra/SoftSchema.pivoted` | same panic | `<relation with Success(HashMap(assetId -> IntT(false), firmware -> …, lastFault -> …, tempC -> …, hoursRun -> …, voltageV -> …))>` |
| `Algebra/SoftSchema.pivotedTyped` | same panic | the same header |

### 2.3 A2 — the piped inputs (20 s cap, `timeout 20 bin/ermine < input`)

| input | BEFORE | AFTER |
|---|---|---|
| `printf 'staircase\n'` | **rc=124** (killed at 20 s), **2,411** `\|>` prompts | **rc=0**, 13.8 s, **0** prompts |
| `printf '"complete"\n'` (E5's) | **rc=124**, **2,378** prompts | **rc=0**, 13.7 s, **0** prompts |
| `printf 'f x = case x of\n'` (a REAL keyword, then EOF) | **rc=124**, **2,493** prompts | **rc=0**, 14.4 s, **1** prompt |
| `printf 'staircas\n'` (control) | rc=0, 0 prompts | rc=0, 0 prompts — output byte-identical |
| `printf 'staircase\n\n'` (control) | rc=0, 1 prompt (the blank line closed the continuation) | rc=0, 0 prompts (no continuation is opened, so the blank line is just an empty command) |
| `printf 'f x = case x of\n  1 -> 2\n\nf 1\n'` | rc=0, 2 prompts, then a syntax error (a PRE-EXISTING limit, §6) | identical, byte for byte |
| `printf '(x -> case x of\n  1 -> 2\n  _ -> 0) 1\n\n'` | rc=0, 3 prompts, `res0 : Int = 2` | identical, byte for byte |
| `printf '(let y = 41 in y + 1)\n\n'` | rc=0, 1 prompt, `res0 : Int = 42` | identical, byte for byte |

The last three are the "the multi-line `case`/`let`/`where` continuation still works" check: the
transcripts (from `Loaded 129 modules` to EOF) compare **IDENTICAL** on all four controls.

---

## 3. The diffs

### 3.1 `core/src/main/scala/com/clarifi/reporting/ermine/session/Lib.scala` (+12 −3)

```scala
-             try { Prim(m.mapValues(_.whnf)) }                                    // record#      :988
+             try { Prim(m.mapValues(_.whnf).toMap) }                              //              :997
-             case Prim(t: Map[String, Runtime]) => Prim(t mapValues (toPrimExpr(_)))    // scalaRecord#   :1007
+             case Prim(t: Map[String, Runtime]) => Prim((t mapValues (toPrimExpr(_))).toMap)  //   :1016
-             case Prim(t: Record) => Prim(t mapValues (fromPrimExpr(_)))                // scalaRecordIn# :1012
+             case Prim(t: Record) => Prim((t mapValues (fromPrimExpr(_))).toMap)          //     :1021
```

plus a nine-line comment above `val rec = …` naming the mechanism and the affected stdlib functions.
`header#` (`:1026`) already had a `.toMap` on its own result and needed none — its panic was
`record#`'s `MapView` arriving, and it is fixed by the first line.

**One semantic note, stated rather than hidden.**  `.toMap` makes `record#` STRICT in each field's
`whnf` at the moment the record is forced, where the `MapView` deferred it (and recomputed it on every
access).  That is what `Record#` is meant to be — a strict `Map[String,Runtime]` — every consumer
iterates the whole map, and `Rec.nf` (`Runtime.scala`) already had the same `.toMap`.  The only
observable change is that a field whose `whnf` throws now makes the whole `record#` a `Bottom` at that
point instead of at first access; before the fix such a record panicked in `scalaRecord#` anyway.

### 3.2 `core/src/main/scala/com/clarifi/reporting/ermine/session/Console.scala` (+22 −3)

```scala
+  private val layoutKeyword =
+    "(?<![A-Za-z0-9_'#])(case|let|where)(?![A-Za-z0-9_'#])".r
+  def opensLayout(s: String): Boolean = layoutKeyword.findFirstIn(s).isDefined

-    val verbose = Set("case","let","where")
-    while ((needMoar || (balanced(input) == Unbalanced) || verbose.exists(input.contains(_))) && !blank) {
+    while ((needMoar || (balanced(input) == Unbalanced) || opensLayout(input)) && !blank) {
       val last = e.readLine("|> ")
-      blank = last == ""
+      blank = (last == null) || (last == "")
       if (!blank) { input = input + "\n" + last }
     }
```

The boundary excludes the characters an Ermine name is built from, `'` and `#` included, so `case'` and
`let#` stay names.  Checked against the reports' own lists: `staircase`, `"complete"`, `palette`,
`delete`, `showcase`, `elsewhere`, `sortShowcase`, `myCase`, `case_1` do NOT match; `case`, `let`,
`where`, `f x = case x of`, `(let y = 41 in y + 1)`, `x where y` do.  E4's `latest` and `casing` contain
none of the three substrings and never matched even before (E4-REVIEW M-5 is right).

### 3.3 `tracker/tools/repl-smoke.sh` (+16 −2)

Each input now runs under `timeout ${REPL_SMOKE_TIMEOUT:-180}` into a raw file, and a non-zero exit
FAILS the check with the code (and says "timed out" on 124).  Without this the new `pipedeof.in` would
have hung the suite for ever on the pre-fix compiler instead of failing it.

---

## 4. Gates

| gate | expected | measured | verdict |
|---|---|---|---|
| `core/test` | 913/914 known + the new properties | **921 passed, 1 failed** — the failure is the known `Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.`  913 + 8 new = 921 | PASS |
| the 8 new properties, pre-fix (negative control) | must fail | **8 of 8 fail** without the `Lib.scala` fix (4 falsified, 4 raised on `extract` of a `Bottom`) | PASS |
| `TestLoopTrace` | 714/714 | `[loop model trace] 714 solves (19 seed x 6 bases + 600 generated); 714 segments; 714 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0`; control 46 of 714 disagree | PASS |
| row trace, 2 corpus groups | byte-identical | `Wide` 566,155 records, `Algebra` 422,039 records, **every non-`rsound` record byte-identical on both**; the only difference is the `rsound ok` records' LAST field, which is `dt / 1000` — elapsed microseconds (`Subst.scala:1269`) — and varies run to run on one build.  With that column blanked, both files are identical | PASS |
| `corpus-run.sh --batch`, 151 files | verdicts unchanged, 82 / 69 | **82 LOADED, 69 REJECTED, 0 UNKNOWN** on both sides.  One file's refutation MESSAGE differs (below) | PASS |
| the modules that panicked | evaluate | all seven bindings in §2.2 evaluate | PASS |
| `sql-render.sh` | renderings unchanged | `diff -rq` over both `sql/` and `out/` is **EMPTY**: all 15 queries and all 15 result tables byte-identical.  30 names asked, 30 answered, 15 produced SQL, on both sides.  The six `q_pivot_*` probes changed message (below) | PASS |
| `repl-smoke.sh` | 35 checks | **rc=0, 5 of 5 PASS, 47 checks** — aliasing 2, relations 6, scoping 4, smoke 23 (= the 35 that existed) plus the new pipedeof 12 | PASS |
| `lsp-smoke.sh` | 98 checks | **rc=0, PASS lsp (98 checks)** | PASS |
| multi-line `case`/`let`/`where` continuation | still works | byte-identical transcripts on all four controls (§2.3) | PASS |
| `.ei` hygiene | none left | final sweep over `core/examples` and `core/src/main/resources/modules` printed nothing | PASS |

### The eight new `core/test` properties (`TestRecordPrims.scala`)

Two shapes of check on purpose.  STRUCTURAL: the Scala object behind the runtime value is a
`scala.collection.immutable.Map` and holds the right entries — a `MapView` fails that directly, which
is the defect rather than its symptom.  RENDERED: the value's own `toString` (`Pretty.ppRuntime`, what
the REPL prints) contains no `<error:` and no `MapView` — which is what a user saw, and which also
catches a `MapView` that travels somewhere new instead of panicking here.

1. `record#` answers a strict `Map`, not a 2.13 `MapView` — and its keys are `{aa, bb}`.
2. `scalaRecord#` forces to a `Record` equal to `Map(aa -> IntExpr(false,1), bb -> IntExpr(false,2))`.
3. `scalaRecordIn#` forces back to a `Record#` (the round trip through all three fixed lines).
4. `Native.Record.header#` reads a forced record's header: `{("aa",IntT(false)), ("bb",IntT(false))}`.
5. `Record.header` forces to a `Row` carrying both field names.
6. `Relation.Predicate.all` builds a real `Predicate` whose `columnReferences` are `{ee, ff}`.
7. **A FORCED PIVOT** — `PivotTest.e` inline, cut to two pivoted columns — reaches
   `Rel(ExtMem(Pivot(_, pivotKey, pivotVals, _, colMap)))` and each part is checked: `pivotKey =
   {Key}`, `pivotVals = {Value}`, `colMap.keySet = {Sector, Price}`, and every entry's key ROW (the
   `record# k` that used to be the `MapView`) is a real `Map("Key" -> StringExpr(false, <column>))`.
   These key rows are the pivot's "rows": one per output column, and forcing them is exactly what
   panicked.
8. The same forced pivot renders with no panic and no `MapView`.

The imports live in the STATEMENT text rather than in `ErmineFixture`'s import map, because
`loadStatements` renders that map as plain `import M` lines and the pivot module needs
`hiding single_Brace; snoc_Brace` (as `PivotTest.e` itself does) to keep `Relation.Row`'s brace
syntax.  Two incidental facts found while writing them, worth knowing: `Prelude` re-exports `Record`
under an affix (`header_Record`), so a module that imports `Prelude` cannot see the bare `header` and
`Record.header` is not a name — `import Record` on its own is what works; and `:import Foo` in the
REPL is matched by `Action.matches` as a prefix of `:imports`, so it prints the session summary and
ignores its argument (`:load` does the importing).

### Why neither fix can touch the loop

The row-solver loop is `Subst.solve` / `Constraints.incorporateAll`, driven from type inference.
`Lib.scala`'s three sites are RUNTIME primitives — they run when a value is forced, which happens after
inference and never during it (a `:load` type-checks without evaluating; that is the whole reason A1
went unnoticed).  `Console.scala` decides how many LINES of REPL input make one command; it is not on
any inference path at all.  The measurement agrees: 566,155 + 422,039 loop records byte-identical, and
`TestLoopTrace`'s 714 segments still agree with the Lean model.

### The two things that DID move, in full

**(a) `sql-render.sh`, the six `q_pivot_*` probes.**  BEFORE: `<error: Panic: unexpected runtime value
in Native.Record.scalaRecord# - MapView(<not computed>)>`.  AFTER: `<error: Don't know how to dump a
mem.>` — the panic is gone and the pivot now reaches the SAME pre-existing wall that
`q_survey_mean`, `q_sales_group`, `q_sales_line` and `q_media_group` already hit (`Scanner.scala:35`,
no `SqlScanner` override for dumping a `Mem`; documented in `sql-render.sh`'s own header).  **A pivot
still renders no SQL**, for a reason that has nothing to do with A1.  `probeScalaRecord` and `probeAll`
likewise stopped erroring.  No `.sql` and no `.txt` changed.  (`q_branch_spread`/`q_branch_usd` name a
different generated temp table on each run — a GUID, not a change.)

**(b) One `shouldfail/` refutation clause — and the experiment that shows it is not ours.**
`Present/shouldfail/chart01_series_not_in_relation.e` stays REJECTED, at the same position `48:15` and
the same field `Present.Shouldfail.Chart01.channelName`, but the CLAUSE moved between the first
pre-fix and the first post-fix 151-file batch:

    A: … 'channelName': the whole contains it but no part does
    B: … 'channelName': a part contains it but the whole does not

That is **ticket B6** ("the blame wording is a propagation reason, not a description, and it varies
with load order; the clause follows the id base"), and the batch corpus run uses the PARALLEL loader.
Three post-fix batches agreeing was NOT enough to say so, so the claim was measured rather than
assumed — 18 runs in all:

| mode | pre-fix build | post-fix build |
|---|---|---|
| per FILE (virgin session, deterministic), x3 each | `the whole contains it…` x3 | `the whole contains it…` x3 |
| batch of the `Present` group only, x3 each | `the whole contains it…` x3 | `the whole contains it…` x3 |
| batch of all 151 files, x3 each | **`whole` , `whole` , `part`** | `part` , `part` , `part` |

**The pre-fix build alone produces BOTH clauses on consecutive runs of the same binary** (`before2`
whole, `before3` part), so the full-corpus batch is nondeterministic in exactly the way B6 describes
and the observed move is not caused by F1.  In the two deterministic modes the two builds agree
exactly.  The VERDICT (`82 LOADED, 69 REJECTED, 0 UNKNOWN`) was identical on all six 151-file runs, and
`after` vs `after2` vs `after3` differ in nothing at all (`0 of 151 files differ`).

---

## 5. Consumers checked

**Every `mapValues`/`Map` site in `Lib.scala` that could carry a record** (grep of `Rec(`, `Prim(… Map`,
`mapValues`, `: Map[String`):

| site | what it does | verdict |
|---|---|---|
| `:997` `record#` | `m.mapValues(_.whnf)` | **FIXED** (`.toMap`) |
| `:1001` `unsafeRecordIn#` | `Rec(p.asInstanceOf[Map[String,Runtime]])` | fixed by `:997` — the unchecked cast now gets a real `Map`; on a `MapView` it would have thrown `ClassCastException` (E1-REVIEW §6.3 predicted this) |
| `:1005–1011` `appendRec#` | `Rec(m ++ m2)` on two `Rec` maps | already a `Map`, untouched |
| `:1016` `scalaRecord#` | `t mapValues toPrimExpr` | **FIXED** (`.toMap`) |
| `:1021` `scalaRecordIn#` | `t mapValues fromPrimExpr` | **FIXED** (`.toMap`) |
| `:1026` `header#` | `recordHeader((r mapValues toPrimExpr).toMap).toList` | already had `.toMap`; its panic was `record#`'s `MapView` arriving, now fixed |
| `:934` `Rec(rec.mapValues(v => Prim(v)).toMap)` (scanner rows) | already `.toMap` | clean |
| `:472/474/476` `Field.cons` / `!` / `\` | `m + (s -> v)`, `m(s)`, `m - s` on `Rec` | `Map` in, `Map` out; clean |
| `:572–583` record restrict / remove | `Rec(r.filterKeys(ks).toMap)`, `Rec(r -- h)` | already `.toMap`; clean |
| `:310–322` `Native.Map` primitives | `m.extract[Map[Any,Runtime]] + / ++ / size / lift` | Ermine `Map` values, no view; clean |
| `:821` | `Prim(Closed(ExtMem(EmptyRel(Map())), Map()))` | literal `Map`s; clean |
| `Runtime.scala` `Rec.nf` | `Rec(t.mapValues(_.nf).toMap)` | already `.toMap`; clean |
| `package.scala:34` `recordHeader` | `t.mapValues(_.typ).toMap` | already `.toMap`; clean |

**Every `record#` / `scalaRecord#` / `scalaRecordIn#` / `header#` consumer in the stdlib**
(`core/src/main/resources/modules`), all of which are fixed by the three lines:

`Record.anyRecordOrd` (`Record.e:21`), `Record.header` (`:24`), `Relation.Pivot`'s
`pivotOnRow`/`pivotOnRowWithDefault` (`Pivot.e:42,47`), `single_Brace`/`snoc_Brace`/`consFulcrum`
(`:64,75,88`), `applyOp`/`mapFulcrum` (`:102,103,108`), `pivot`/`pivotWithDefault` (`:112,116`),
`Relation.nonEmptyRelation` (`Relation.e:34`), `Relation.Predicate.all` (`Predicate.e:77`),
`Layout.Chart.srecKeys` (`Chart.e:188`), `Layout.Presentation`'s `extract#` path
(`Presentation.e:82`), `Relation.Sort.partialRecordOrd` (`Sort.e:109`), and
`Layout.Report`'s two `unsafeRecordIn# . scalaRecordIn#` sites (`Report.e:1594,1608`).

**NOT affected, checked and confirmed:** `Relation.relation` (`Relation.e:24`) is `mkRelation# (toList# r)`
and never touches `record#` — which is why the 15 SQL renderings worked before the fix and are
byte-identical after it.  `Relation.rheader#` (`Relation.e:57`) calls a DIFFERENT primitive,
`Relation.header#` (`Lib.scala:781`, `Relation# -> …`), not `Native.Record.header#`.
`Layout/Report.e:622`'s `lmap unsafeRecordIn#` receives a scanner row, not a `record#` result.

**The `Native/*.e` foreign bindings.**  The only module that mentions `Record#`/`ScalaRecord#` at all is
`Native/Record.e`, whose one foreign binding is `anyRecordOrd## = com.clarifi.reporting.package.RecordOrder`,
an `Order[Record]` (no `mapValues`).  The other `ScalaRecord#` foreign methods are
`Relation/Predicate.e:36` (`Predicate$.fromRecord`, whose `tup.toSeq` now sees a real `Map`),
`Layout/Presentation.e:29` (`extract`), `Relation/Sort.e:133` (`scalaRecordOrd#`) and
`Layout/Chart/Unsafe.e:101–115` / `Layout/Report.e:1588,1597` (types only).  All receive
`scalaRecord#`'s output and are improved, none needed a change.

**Every `readLine` in the tree** (the A2 half):

| site | handling of `null` | verdict |
|---|---|---|
| `Console.scala:146` the wrapper itself | turns `EndOfFileException` into `null`, `UserInterruptException` into `""` | left as it is — the callers are what must cope |
| `Console.scala:640` in `other` | was `blank = last == ""` | **FIXED** — `null` now ends the continuation |
| `Console.scala:744` in `repl` | `while (!e.quit && { line = e.readLine(">> "); line != null })` | already null-safe; unchanged |
| `Console.scala:323` `:paste` | passes the clipboard text to `other`, so it inherits the fix (and no longer opens a continuation on a pasted `staircase`) | clean |
| `lsp/Rpc.scala:315` | private, returns `Option[String]`, `None` at EOF; both call sites (`:255`, `:266`) test `isEmpty` | clean |
| `machines/…/Example.scala:35` | `Option(r.readLine)` | clean |

## 6. Not done, and known limits left in place

* **A7 and A8 are NOT fixed** (per the brief) and neither fix touches their paths.  A7 (a foreign
  exception becomes a `Bottom` VALUE, `Runtime.scala:51`) sits on the path the A1 fix uses: `Prim(…)`
  takes its argument by name inside a `try`, so `.toMap` forcing a field that throws now yields a
  `Bottom` for the whole record at that point.  That is A7's existing mechanism, unchanged in kind —
  before the fix such a record panicked in `scalaRecord#` regardless.  A8 (`File.readFile` traces
  through `System.console()`) is entirely in the STDLIB, on a path F1 never touches: `File.e:23`'s
  `withSource#` calls `traceShow` (`IO.e:76`) -> `trace` (`:70`) -> `printLn` (`:67`) ->
  `writer# mkConsole`, and `mkConsole` is the foreign binding `function "java.lang.System" "console"`
  at `IO.e:59`.  `Console.scala` neither defines nor calls it — the whole chain is Ermine plus one
  foreign function, and no line of it changed.
* **A keyword inside a string literal still opens a continuation.** `"where to?"` matches the token
  test.  It costs one extra `|>` line and, since the null-EOF fix, always terminates.  Stripping
  string literals before the test was deliberately not done: it is a second parser in a heuristic, and
  the unbounded-loop half is what made this a bug.  Recorded in the code comment.
* **The REPL still cannot parse a multi-line `f x = case x of` definition** — the continuation now
  collects the lines correctly and the parser then refuses them
  (`expected '{', eof, module header, semicolon, or whitespace`).  That is the pre-existing D3 limit
  named in `Console.other`'s own comment ("the fused `StatementParsers.multiline` probe is gone"), it
  behaves identically before and after this change, and `pipedeof.expected` pins it so a later fix has
  to update the golden file deliberately.  Not in F1's scope.
* **A pivot still renders no SQL** (`Don't know how to dump a mem`, `Scanner.scala:35`).  Out of scope,
  and now indistinguishable from every other `Mem`.
* **`sql-render.sh`'s `q_branch_spread`/`q_branch_usd`** name a freshly generated temp table on every
  run, so their ERR text differs run to run.  Pre-existing, not a change.
* **The `rsound` trace records carry a wall-clock microsecond field**, so a `-Dermine.rowTrace` file is
  not byte-comparable as a whole between two runs even of one build.  Compare with column 8 of the
  `rsound` lines masked (as §4 does), or compare only the loop records.  Worth a line in whatever
  tooling next asserts "the trace is byte-identical".

