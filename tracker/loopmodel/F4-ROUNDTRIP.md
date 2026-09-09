# F4 — the interface round-trip bug (ticket E1): a published concrete row with a lower-case label never warm-reads

Stage F4, 2026-09-09.  Brief `tracker/loopmodel/briefs/brief-F4.md`; ticket
`tracker/TICKET-stdlib-findings.md` E1.  Branch `scala3-migration`, from `6701ab0`.
**Outcome: GREEN** — a one-line parser fix, no published byte moves, three new properties (all three
measured RED on the pre-fix compiler), every gate green, and the warm corpus load down from
35.5–36.2 s to 23.5–24.2 s.  Scope re-measured: **70 of 241** corpus interfaces, not 18, and the
ticket's narrowing to "a partition with a concrete part" is corrected in §1.

**The cause in one sentence.**  `Pretty.ppName` spells a concrete row's field label FULLY QUALIFIED
(`(|Currency.currencyCode|)`) and `TypeParsers.rho`'s dotted-name parser accepted only
`Upper(.Upper)+`, so every label whose last segment starts lower case was unreadable, `preCk`
answered `None`, and the module was fully rechecked and its `.ei` rewritten on every load.

## 1. Reproduction (F4.1)

The reviewer's probe, `review-S5/probe/ConcProbe.e`, copied to the scratch tree and loaded twice with
interfaces on (`bin/ermine`, `ermine.useInterface` defaults true).  The observable is the `.ei`'s
mtime: `writeInterface` runs on every `CheckMethod.Full` and on no `CheckMethod.Interface`.

A seven-module battery separates the shape from the label, one `bin/ermine` invocation each, mtimes
compared across the two loads:

| probe | published signature (the `.ei` line, key header stripped) | 2nd load |
|---|---|---|
| `F01Part` | `sig : forall (r: rho). r <- ((\|F01Part.foo\|), h) => Builtin.Relation r -> Builtin.Relation r` | **REWRITTEN** |
| `F02PartUpper` | `… r <- ((\|F02PartUpper.Foo\|), h) => …` | warm |
| `F03TypeArg` | `sig : Builtin.Relation (\|F03TypeArg.foo\|) -> Builtin.Relation (\|F03TypeArg.foo\|)` | **REWRITTEN** |
| `F04TypeArgUpper` | `… Builtin.Relation (\|F04TypeArgUpper.Foo\|) …` | warm |
| `F05Record` | `sig : Builtin.Record (\|F05Record.foo\|) -> Builtin.Record (\|F05Record.foo\|)` | **REWRITTEN** |
| `F06Multi` | `… r <- ((\|F06Multi.foo, F06Multi.bar\|), h) => …` | **REWRITTEN** |
| `F07Empty` | `sig : Builtin.Relation (\|\|) -> Builtin.Relation (\|\|)` | warm |

**The ticket's narrowing is wrong, and this is the first correction.**  It is NOT "only a concrete
row as a PART of a partition".  It is a concrete row carrying a LOWER-CASE label, in ANY position: as
a part (`F01`), as a type argument to `Relation` (`F03`) or to `Record` (`F05`).  The reason the
stdlib looked clean is that the only concrete-row label the BOOTED stdlib publishes is `Field.Count`
— upper case.  `Currency.ei`, whose labels are `Currency.currencyName` and friends, is NOT among the
129 modules a plain REPL boot loads at all (the only importer of `Currency` in the whole tree is
`core/examples/Time/MultiCurrencyPnl.e`), and when the corpus pulls it in it does NOT warm-read
either — measured below.  So the ticket's "129 of 129 stdlib interfaces warm-read, `Currency.ei`
included" is wrong twice over.

The parse error itself, obtained by reading the probe's `.ei` back through `G1Compare --pair` (which
uses the same `InterfaceParsers.interfaceSigs`):

```
ConcProbe.ei:1:42: expected ',', '|)', or whitespace
cSig : forall (r: rho). r <- ((|ConcProbe.foo|), h) => Builtin.Relation r -> Builtin.Relation r
                                         ^
ConcProbe.ei:1:31: note: unmatched '(|'
```

Column 42 is the `.` in `ConcProbe.foo`: the row parser read `ConcProbe` as a bare label and then
wanted `,` or `|)`.

## 2. The cause, and which side is wrong (F4.1)

**The PARSER.**  `Pretty.formatRho` prints each field of a `ConcreteRho` with `ppName` under
`FullyQualified`, and `Pretty.qualifiedGlobal` renders `Global(m, n, Idfix)` as `m + "." + n` with no
regard for `n`'s case.  `TypeParsers.rho` (`:164`) read that back with

```scala
if (u.recognizedCons.nonEmpty) dottedName.attempt | typeName else typeName
```

and `dottedName` is `(upperName >> (ch('.') >> upperName).skipSome).slice` — EVERY segment must start
upper case.  That is right for `dottedName`'s other caller, `interfaceCon`, where the name is a type
CONSTRUCTOR, and wrong for a field label.  `typeName` then matched the leading `ConcProbe` and the row
ended at the dot.

`recognizedCons` is non-empty only when an interface is being parsed (`Session.dep`'s `preCk`, and
`G1Compare`), so this branch is interface-only and the source language is not involved either way.

### Every published form, ticked against the parser

`Pretty.ppType` is the whole printer; `Dep.writeInterface` is its only interface caller, through
`prettyVarHasType(_, FullyQualified)`.

| # | `ppType` case | published spelling | read by | ✓/✗ |
|---|---|---|---|---|
| T1 | `Forall` | `forall {k…} (v: κ)… . C => body` | `typ`'s `uQuant`, `doubleArrow` | ✓ |
| T2 | `Exists` | `(exists (v: κ)… . c1, c2)` | `exists` in `anyTyp` | ✓ |
| T3 | `Memory` | prints the body, drops the wrapper | — | ✓ (not a type difference) |
| T4 | `ProductT(n)` | `(,,)` | `typL0`'s `paren(comma.many)` | ✓ |
| T5 | `VarT` | the variable's display name | `typeVar` | ✓ |
| T6 | `Arrow` | `(->)` | `typL0`'s `paren(keyOp("->"))` | ✓ |
| T7 | `ConcreteRho` | `(\| n1, n2 \|)` | `banana(rho(l))` | see N1–N8 |
| T8 | `Con` | `Builtin.Relation`, `(Mod.++)` | `interfaceCon` (`dottedName` / `dottedOpName`) | ✓ |
| T9 | `AppT` | prefix application, `a -> b`, `(a, b)` | `typL1` / `typL2` | ✓ — under `FullyQualified` `ppAppNT`'s FIRST case fires for every `Global`, so the infix/prefix/postfix spellings (`x <>_Mod y`) are never published |
| T10 | `Part` | `l <- (r1, r2)` | `partition` (`keyOp("<-")`) | ✓ — but `Part.apply` REVERSES the right-hand side, so a re-parse is `Part(l, [r2, r1])`.  Benign (the solver treats the rhs as a multiset) and pre-existing; it is why an `.ei` is not a byte fixed point (§5) |

Names inside a `(\| … \|)` — `formatRho` → `ppName` under `FullyQualified`:

| # | `Name` | published spelling | pre-fix | post-fix | reachable? |
|---|---|---|---|---|---|
| N1 | `Global(m,n,Idfix)`, `n` upper-case initial | `Field.Count` | ✓ `dottedName` | ✓ `dottedFieldName` | yes — 53 occurrences in the corpus |
| N2 | `Global(m,n,Idfix)`, `n` lower-case initial | `Currency.currencyCode` | **✗ — THE BUG** | ✓ | yes — **7,448** occurrences |
| N3 | `Global(m,n,Idfix)`, `n` with `#`, `'`, `_` | `M.foo#bar` | ✗ (lower) / ✓ (upper) | ✓ (`tailChar` admits all three) | yes — probe `F09Odd` |
| N4 | the empty row | `(\|\|)` | ✓ (`sepBy` admits zero) | ✓ | yes — 34 occurrences |
| N5 | `Local(n, Idfix)` | `foo` | ✓ `typeName`, then re-qualified with the READING module | ✓ | never published: `rho` globalises every label at parse time (0 of 7,535) |
| N6 | `Local(n, Idfix)`, abnormal | `` ``a b`` `` | ✓ `literalIdent` | ✓ | unreachable — but NOT for N8's reason: the SOURCE row grammar refuses a literal ident (probe `F08Literal`; the reviewer tried `(\| ``a b`` \|)`, `(\| ``ab`` \|)`, `type R = (\| ``a b`` \|)`, all syntax errors) and `fieldStatementP` refuses to declare one.  `TypeNameParsers.ident` is `super.ident \| literalIdent`, so the INTERFACE grammar alone would look permissive |
| N7 | `Global(m,n,Idfix)`, abnormal | `M.a b` — `qualifiedGlobal` does NOT back-quote under `FullyQualified` | ✗ | ✗ | unreachable, same reason as N6.  A PRINTER defect, left standing and recorded in the ticket |
| N8 | any `Name` with `Infix`/`Prefix`/`Postfix` fixity | `(M.++)`, `(prefix M.!)` | ✗ (`typeName`'s `paren(opName)` reads a bare operator, and only one already in `canonicalTypes`) | ✗ | unreachable: `SurfaceParsers.fieldStatementP` takes `identTok`, so a declared field label is always `Idfix`; and the reviewer tried the tree's two REAL type-level operators (`Type/Cast.e`'s `<:`, `Constraint.e`'s `\|`) in a row, both refused |

So of the eight name forms the printer can emit into a row, two (N7, N8) are unreadable and neither is
reachable from Ermine source — by two DIFFERENT mechanisms, which the first draft of this report and of
the ticket ran together (F4-REVIEW R-6a): the source ROW grammar refuses a back-quoted label (N6/N7),
and `fieldStatementP` refuses to declare an operator-named one (N8).  The reviewer reached neither in
six attempts.  The reachable gap is exactly N2/N3, and it is the parser's.

### Scope, re-measured

`bin/ermine` over the 154-file corpus (`corpus-run.sh --batch`'s file list, interfaces ON), run twice:
**70 of 241 interfaces are rewritten on the second run, and on every run after.**  (241 = 156 under
the stdlib tree — the boot's 129 plus 27 more the examples import — and 85 in `core/examples`, one
per module that loads.)  A label census over
all 241 gives 7,448 dotted-lower / 53 dotted-upper / 34 empty and no other shape, and the set of files
holding at least one dotted-lower label is EXACTLY the set of files rewritten — 70 = 70, no cascade,
no false positive.  Two are stdlib (`Currency.ei`, `Layout/Report/Relation.ei`); 68 are examples.

The ticket's "18 of 268" counted only the interfaces publishing the PARTITION shape.  In this tree that
shape appears in 14 interfaces, 13 of which are affected (`PivotTest.ei`'s parts carry upper-case
labels).  The real predicate is the label, not the shape, and it is five times as many files.

## 3. The fix (F4.2)

`core/src/main/scala/com/clarifi/reporting/ermine/parsing/TypeParsers.scala`, on the PARSER side, so
no published byte moves:

```scala
  private def dottedFieldName: Parser[Global] =
    (upperName >> (ch('.') >> anyName).skipSome).slice.filter { s =>
      s.substring(0, s.lastIndexOf('.')).split('.').forall(_.charAt(0).isUpper)
    } map { s =>
      val n = s.lastIndexOf('.')
      Global(s.substring(0, n), s.substring(n + 1))
    }

  private def anyName : Parser[Unit] = letter >> tailChar.skipMany
```

The `filter` is the fix round's (F4-REVIEW R-4).  Without it every segment after the first could start
lower case, so `(|Mod.foo.bar|)` parsed as `Global("Mod.foo", "bar")` — harmless, since nothing emits
it and the split at `lastIndexOf('.')` stays exact, but wider than the printer and wider than the
scaladoc claimed.  With it the parser accepts EXACTLY what `qualifiedGlobal` can emit: an upper-case
module path, then one label of any case.  The check lives on the slice rather than in the grammar
because the two halves cannot be separated by a parser without lookahead — the module path and the
label are both `.`-separated identifiers, and a grammar greedy enough to read
`Layout.Report.Relation.groupId` would eat `Count` out of `Field.Count`.  The upper-case module path
is not a guess either: `SurfaceParsers.moduleNameTok` requires every segment of a module NAME to start
upper case (the reviewer checked that `module lower where` is a syntax error and that a header-less
file does not load at all), so a lower-case module segment cannot reach an interface.

and `rho` uses `dottedFieldName.attempt | typeName` in place of `dottedName.attempt | typeName`.
`dottedName` itself is untouched, so `interfaceCon` still requires an upper-case constructor.
`dottedFieldName` SUBSUMES `dottedName` in this position (an upper-case final segment is an ordinary
identifier too), which is why `Field.Count` still reads as `Global("Field","Count")` — N1 above.

`Session.interfaceFormatVersion` is NOT bumped and must not be: every `.ei` written by the pre-fix
compiler is byte-valid and now readable.  Measured: the post-fix compiler read the 241 interfaces the
pre-fix compiler had written and rewrote **0** of them.

## 4. Tests (F4.3)

New file `scalacheck-binding/src/main/scala/TestInterfaceConcreteRow.scala`, three properties, in
`TestInterfaceRoundTrip`'s / `TestInterfaceKey`'s style (own temp workspace, `Session.depCache.clear()`
under `ErmineFixture.literalLock`, modules owning every interface they depend on — `RowConc` imports
NOTHING, for the reason `TestInterfaceKey` documents).

1. **`warm read of a published concrete row`** — a module publishing `rSig : r <- (h, (|foo|)) => …`,
   a concrete row as a plain type (`tSig`), an upper-case control (`uSig`) and the `#`/`'`/`_`
   label characters (`oSig`).  Asserts the cold load is `Full` and writes an `.ei`, that the `.ei`
   really does carry the partition and the lower-case label (so a future printer change cannot make
   the property vacuous), that the warm load is `CheckMethod.Interface`, and that the warm load did
   not touch the file.
2. **`every corpus interface warm-reads, and none is rewritten`** — the whole corpus (161 stdlib
   modules + the seven non-`shouldfail` `core/examples` directories) is staged into a temp tree and
   loaded with interfaces on, then loaded AGAIN in a fresh session over the same tree: every module
   with an `.ei` must be `CheckMethod.Interface` and no `.ei` may be rewritten.  245 interfaces.
   This is criterion (3) of the ticket at unit-test scale, and it exercises the grammar through the
   REAL reader (`Session.dep`'s `preCk`, with the module's own parse state), not a hand-built one.
3. **`every corpus interface parses and re-prints stably`** — the grammar property.  Every one of the
   245 `.ei` parses with `InterfaceParsers.interfaceSigs`, re-prints through the printer
   `Dep.writeInterface` uses, re-parses, and the re-parse is ALPHA-EQUIVALENT to the first parse.
   2,000+ signatures.

Two fixture notes, both from the fix round.  `ErmineFixture.literalLock` is held across the corpus
staging, BOTH loads, every `Session.depCache.clear()`, the mtime sleep and the comparison — the
`TestInterfaceKey` discipline, stated at the fixture's definition (R-1).  And the suite deletes what it
stages: the ~3.5 MB corpus tree is removed by a reference-counted `finally` in each of the two
properties that share it, a stale-tree sweep removes `ermine-ei-corpus*` directories older than an
hour, and property 1's own workspace is deleted the same way, so nothing is left in the system temp
directory (R-5; measured, 0 trees after three consecutive runs).

**Negative control (all three fail before the fix).**  With `rho` reverted to `dottedName` and nothing
else changed:

```
! Interface concrete row.warm read of a published concrete row: warm Some(Full) (the .ei did not read back)
! Interface concrete row.every corpus interface warm-reads, and none is rewritten:
      70 of 245 interfaces were rewritten on the second load
! Interface concrete row.every corpus interface parses and re-prints stably:
      70 of 245 interfaces did not round-trip (134 of 245 re-print byte-identically)
```

70 of 245 in the test's temp tree and 70 of 241 in the repository tree: the same 70 modules.  The two
totals differ by four because the test stages and loads the corpus by MODULE NAME while
`corpus-run.sh` loads by file path, so a handful of stdlib modules the batch does not reach are
published in the test tree; the affected set is identical either way.

### Why property 3 says "alpha-equivalent" and not "the same bytes"

It cannot say the same bytes, and the reason is not this bug.  Three mechanisms move the spelling
without moving the type:

* `Part.apply` REVERSES the right-hand side (its fold conses), so `r <- (h, t)` parses to
  `Part(r, [t, h])` and re-prints as `r <- (t, h)` — an oscillation of period two;
* an existential's binder list and constraint list come back in an id-derived order, and the ids are
  freshly drawn on every parse;
* ticket B3: the printer publishes a free row variable it does not bind, and `qtyp` binds those on the
  way in, so a re-print carries a WIDER quantifier than the file did.

Measured on the corpus: **196 of 245 interfaces do re-print byte-identically**; the other 49 differ
only in the ways above.  The property reports that count (`Prop.collect`) and asserts the
alpha-equivalence, which is the statement that survives.  Making byte-identity attainable is a
canonicaliser — `ROSE-COMPARISON.md` §3 rank 3 — and is not F4's.

The comparison used is a local `aeqs` that differs from `G1Compare.alphaEq` in **exactly one** way,
and it is not a relaxation: it answers EVERY bijection, lazily, instead of the first one it finds.
Binders are paired exactly as `G1Compare` pairs them — `Forall` POSITIONALLY, `Exists` lazily through
the constraint multiset — so no quantifier reordering is forgiven that `G1Compare` would not forgive.

The completeness IS load-bearing and the positional relaxation is not; both halves are measured, and
the second measurement is the reviewer's (F4-REVIEW R-3), adopted in the fix round:

* plain `G1Compare.alphaEq` in place of `aeqs` falsifies property 3 on **15 of 245** interfaces
  (`Relation.ei :: joinWithDefault, lookbackJoin, setColumn`, `Op.ei :: %, *, +`,
  `Predicate.ei :: !=, &&, <`, `Helpers.ei`, `Signatures.ei`, `Legendary.ei`, `PresRow.ei`,
  `RTree.ei`, …) — so the search must be complete.  `G1Compare` already matches a `Part`'s rhs and an
  `Exists`' constraints as multisets (`matchMultiset`); what it cannot do is offer a SECOND match when
  the first one is contradicted later, and inside `c <- (rs, so)` against `c <- (so, rs)` the first
  match is the swap;
* the first draft ALSO opened `Forall` binders lazily.  With the complete search in place that buys
  nothing — property 3 passes on all 245 with `Forall` paired positionally — so it was dropped, and
  the property is strictly stronger for it.

Neither `aeqs` nor `G1Compare.alphaEq` compares binder KINDS; that hole is inherited, not opened.

## 5. The affected interfaces, before and after (F4.3 item 3)

Two consecutive `bin/ermine` batch runs over the 154-file corpus with interfaces ON, `.ei` mtimes
compared:

| | rewritten on the 2nd run |
|---|---|
| pre-fix | **70 of 241** |
| post-fix, against the interfaces the PRE-FIX compiler wrote | **0 of 241** |
| post-fix, two consecutive post-fix runs | **0 of 241** |

The 70 (2 stdlib + 68 examples):

```
    example Accumulate
    example Ai/BatteryCycling
    example Ai/ClinicalTrial
    example Ai/FiscalCalendar
    example Ai/GridTelemetry
    example Ai/HeadcountPlan
    example Ai/IncidentSeverity
    example Ai/RevenueByPeriod
    example Ai/SalesByRegion
    example Ai/SupplyChainInventory
    example Ai/TelescopeTime
    example Algebra/BillOfMaterials
    example Algebra/Comprehensions
    example Algebra/Customer360
    example Algebra/Deduplication
    example Algebra/InventorySnapshots
    example Algebra/KeyDiscipline
    example Algebra/LedgerScan
    example Algebra/ManagerChains
    example Algebra/OrderLedger
    example Algebra/RateStatistics
    example Algebra/SoftSchema
    example ChartsExample
    example GridExample
    example GroupBy
    example Lang/CsvIntake
    example Lang/DoNotation
    example Lang/ForeignJdk
    example Lang/FreeReportDsl
    example Lang/ProjectionCliff
    example Lang/ReaderParams
    example Lang/RunningState
    example Lang/Signatures
    example Lang/StatementParser
    example Lang/TextTables
    example Lang/TreeAndMap
    example Lang/TypesAndRows
    example Present/AtomicAndRelation
    example Present/DrilldownExplorer
    example Present/FulcrumPanel
    example Present/ProjectionCost
    example Present/SalesDashboard
    example Present/SevenReads
    example Present/SortShowcase
    example Present/StyleGridHeatmap
    example Present/ValidationReport
    example Present/VarianceStyling
    example Present/WildChain
    example Present/WriterOutputs
    example SoftRelation
    example Time/CohortRetention
    example Time/DemandForecast
    example Time/EmployeeTenure
    example Time/FiscalTree
    example Time/InterestAccrual
    example Time/MultiCurrencyPnl
    example Time/ReadingHistory
    example Time/SensorSeries
    example Time/SubscriptionWaterfall
    example Wide/BranchDeposits
    example Wide/ClaimsExperience
    example Wide/Leaderboard
    example Wide/MediaSpend
    example Wide/RevenueShare
    example Wide/SalesLedger
    example Wide/SurveyPanel
    example Wide/TrialBalance
    example Wide/WardRoster
    stdlib  Currency
    stdlib  Layout/Report/Relation
```

Every one of the 70 warm-reads after the fix, and the 171 that already warm-read still do.

## 6. Timing (F4.4)

The payoff is the full inference those 70 modules paid on every load of an otherwise warm tree.
Measured as the wall time of `bin/ermine` over the 154-file corpus batch with interfaces ON, on a
tree whose interfaces are already written (i.e. the WARM load), `ERMINE_JAVA_OPTS="-Xmx2g
-XX:ActiveProcessorCount=2"`, one JVM at a time:

INTERLEAVED, as the gate policy requires of a perf figure — old / new / old / new, one JVM at a time,
each side reading a tree the other side wrote.  That is legitimate here because the strong claim was
measured directly: the post-fix compiler read all 241 interfaces the pre-fix compiler had written,
rewrote 0 and moved 0 bytes.  It is NOT because an `.ei`'s bytes are absolutely stable — they are
not, and the F4 review's R-2 measured that on the PRE-FIX compiler alone: a cold-written tree and a
warm-written tree differ in **16 of 241** interfaces, in quantifier shape, in an existential binder's
kind and in constraint order.  That is now ticket **E3**, and it is a standing hazard for any `.ei`
byte comparison, the Tier 1 sweep included.

| order | side | wall | the stdlib boot inside it |
|---|---|---|---|
| 1 | post-fix | **23.98 s** | 6.86 s |
| 2 | pre-fix  | **35.45 s** | 6.33 s |
| 3 | post-fix | **23.53 s** | 6.54 s |
| 4 | pre-fix  | **36.01 s** | 6.67 s |
| 5 | post-fix | **24.21 s** | 7.04 s |

plus the two runs taken before the A/B was set up: pre-fix 36.22 s / boot 6.96 s, post-fix 24.20 s /
boot 6.82 s.  So **pre-fix 35.45 / 36.01 / 36.22, post-fix 23.53 / 23.81 / 23.98 / 24.20 / 24.21** —
the two bands do not overlap and the gap is **12 s, a third of the warm load**.

These are not machine-exact.  The reviewer's independent interleaved run on the same machine, with a
pre-fix build compiled from `git show HEAD:…/TypeParsers.scala`, sits about half a second higher on
the pre side and inside the band on the post side: **pre 36.11 / 36.38 / 36.54 / 36.74 / 37.02, post
23.61 / 24.04 / 24.08 / 24.27**, gap ~12.3 s (F4-REVIEW R-6b).  Same conclusion, disjoint bands; read
the gap, not the digits.

The stdlib BOOT does not move (6.33–7.04 s on both sides, indistinguishable), and that is the right
answer: neither `Currency` nor `Layout/Report/Relation` is among the 129 modules a boot loads — they
are two of the 27 extra stdlib modules the examples pull in.  The whole saving is the full inference
the 68 affected example modules used to pay on every load of an otherwise warm tree.

## 7. Gates (F4.4)

Tier 0 in full, plus Tier 1's `g1-validate.sh`.  The interface SWEEP (`ei-diff.sh`) is not run and is
not required: the fix is on the READER, and the stronger statement is already measured — the post-fix
compiler read 241 interfaces written by the pre-fix compiler and rewrote none, so not one published
byte moved.

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | clean (the one pre-existing `TypeParsers.scala:76` pattern warning) |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**, hashdiff 0, eqdiff 0; 3 properties green |
| `tracker/tools/corpus-run.sh --batch` | **85 LOADED / 69 REJECTED / 0 UNKNOWN**, 154 total |
| `tracker/tools/repl-smoke.sh` | all green — `ffi-tolerant` 9, `pipedeof` 12, `relations` 6, `scoping` 4, `smoke` 23, `tauto` 5 |
| `tracker/tools/lsp-smoke.sh` | **PASS lsp (185 checks)**; the LSP boot still 129 modules |
| `tracker/tools/g1-validate.sh` | **9/9** — 7 fixtures, double-run self-agreement (129 files, 1,447 signatures, EQUIVALENT), no drift from `tracker/g1-baseline`.  The baseline is NOT re-cut: nothing moved |
| `sbt core/test` | **943 / 943**, 0 failed, 0 errors, 1,377 s.  940 pre-existing (the count F3 and S5 record) plus this stage's three.  **INTERMITTENT, and the gate must be read that way** — see below.  The `TestConstraints."disjunction sound"` quarantine is unchanged (registered only under `-Dermine.test.disjunction=true`) |
| corpus double run, interfaces ON | 0 of 241 rewritten (§5) |

### `core/test` is not deterministic (F4-REVIEW R-1, ticket E4)

My run was 943/943.  The reviewer's FIRST run of the same tree was `Total 943, Failed 0, Errors 1,
Passed 942` (1,453 s) — `TestLower :: "3.4a.negation applies primNeg to the whole chain"` raising
`scalaparsers.Death: Module not found: 'Test'` — and the SECOND, unchanged, was 943/943 (1,356 s).
The new suite's three properties are green in both runs, and the flake does not reproduce in
isolation (`TestLower` alone 2× = 28/28; `TestLower` with `TestInterfaceConcreteRow` 2× = 31/31).

It is not the parser change: `TestLower` exercises the lowering pipeline, not the interface grammar.
It is stage S5's hazard — six suites (`TestNewPipeline`, `TestLower`, `TestTolerantCheck`,
`TestTolerantRead`, `TestStage1Pins`, `TestEditorBuffers`) touch `Session.depCache` /
`Session.loadModules` WITHOUT `ErmineFixture.literalLock`, and `ErmineFixture.baseEnv`'s dynamic
`Test` module is what goes missing.

**Does F4's suite make it worse, and can F4 close it?**  It lengthens the window and cannot close it.
The suite is already on the correct side of the discipline: `TestInterfaceConcreteRow` holds
`ErmineFixture.literalLock` across the corpus staging, BOTH loads, every `Session.depCache.clear()`,
the mtime sleep and the comparison, exactly as `TestInterfaceKey` holds it across its five loads —
checked in the fix round and now stated at the definition of the `corpus` fixture.  Nothing this suite
does touches the dep cache outside the lock.  But it holds that lock ~85 s per run and clears the
cache five times, which is a longer quiet period for a lock-free suite to be unlucky in.  Locking
harder here cannot help: the six offenders never take the lock, so no discipline in a compliant suite
excludes them.  The fix is theirs, and it is ticket **E4**.


Files changed:

* `core/src/main/scala/com/clarifi/reporting/ermine/parsing/TypeParsers.scala` — `dottedFieldName`
  (new, 5 lines + `anyName`), used by `rho` in place of `dottedName`;
* `scalacheck-binding/src/main/scala/TestInterfaceConcreteRow.scala` — new, three properties;
* `tracker/TICKET-stdlib-findings.md` — E1 marked, with the correction to its scope and narrowing;
* `tracker/LOOP-MODEL-PLAN.md` — the F4 row;
* this report.

No `.ei` under `tracker/g1-*` was touched; every `.ei` this stage caused outside the corpus tree was
deleted.  `tracker/lean/` is untouched and no Lean was built.  Nothing is committed.

## 8. What F4 did NOT do

* The interface FORMAT is unchanged and `interfaceFormatVersion` stays at `2` — deliberately, since
  every existing `.ei` is now readable rather than stale.
* The two unreachable printer defects (N7, N8 in §2) are recorded in ticket E1, not fixed: fixing
  either moves published bytes for a form nothing can produce.
* Ticket **E2** (the write side frozen into the cached `Dep`) is untouched and still open.  It is the
  other half of section E and is independent of this one.
* Byte-identical re-printing is not attained and is not attainable without a canonicaliser
  (`ROSE-COMPARISON.md` §3 rank 3); §4 says exactly what stands in the way and what the property
  asserts instead.

## Fix round (F4 review)

`tracker/loopmodel/F4-REVIEW.md`, verdict **ADVANCE** — the reviewer reproduced the cause on a pre-fix
build compiled from `git show HEAD:…/TypeParsers.scala`, re-derived the census to the digit
(7,448 / 53 / 34, 70 files = the 70 rewritten, `other 0`), reproduced the negative control with every
figure, checked that SOURCE parsing is byte-identical across the change (eleven probes, diagnostics
line for line), reached neither N7 nor N8 in six attempts, and re-ran every gate.  Six findings, no
defect in the parser change, the tests, the census or the measurement.  All six are addressed here.

| # | rank | what it said | what I did |
|---|---|---|---|
| **R-1** | medium | `core/test` is INTERMITTENT — the reviewer's first run was 942 passed / 1 error in `TestLower` (`Death: Module not found: 'Test'`), the second 943/943; six suites touch the process-global dep cache without `ErmineFixture.literalLock`, and the new suite lengthens that window.  Also: check the new suite holds the lock across BOTH loads | **Recorded, and the lock CHECKED.**  §7 now says the gate is intermittent and carries the reviewer's two runs; ticket **E4** opened with the mechanism, the six suites, the four isolation runs and acceptance criteria.  The lock check: `TestInterfaceConcreteRow` already held `literalLock` across the staging, BOTH passes, every `depCache.clear()`, the mtime sleep and the comparison — nothing changed, and that is now stated at the `corpus` fixture's definition with the reason it CANNOT close the window (the six offenders never take the lock) |
| **R-2** | low-medium | §6's "the bytes are identical" overstates: on the PRE-FIX compiler alone a cold-written and a warm-written tree differ in 16 of 241 interfaces (quantifier shape, an existential binder's kind, constraint order).  Deserves a ticket | **Both.**  §6's parenthetical is replaced by the measured statement (post-fix read 241 pre-fix interfaces, rewrote 0, moved 0 bytes) with the regime named; ticket **E3** opened with the reviewer's measurement, why it is a hazard for every future `.ei` byte comparison including the Tier 1 sweep, the cross-reference to **B3**, and acceptance criteria |
| **R-3** | low | Property 3's `aeqs` has two departures from `G1Compare.alphaEq` and only one is needed: variant A (plain `alphaEq`) falsifies on 15 of 245, so COMPLETENESS is load-bearing; variant B (complete search, positional `Forall`) PASSES, so the `Forall` relaxation buys nothing | **Relaxation dropped.**  `Forall` binders are now paired POSITIONALLY, exactly as `G1Compare` pairs them; the only remaining difference is that the search answers every bijection instead of the first.  Property 3 passes on all 245, three runs alone.  §4 says which relaxation remains (none) and carries both of the reviewer's measurements |
| **R-4** | nit | `dottedFieldName` let EVERY segment after the first start lower case, so `(\|Mod.foo.bar\|)` parsed — harmless but wider than the printer and wider than its own scaladoc | **Tightened.**  A `filter` on the slice requires every segment of the MODULE path to start upper case; only the label may not.  The check is on the slice, not in the grammar, because the two halves cannot be separated without lookahead — a grammar greedy enough for `Layout.Report.Relation.groupId` would eat `Count` out of `Field.Count`; the scaladoc now says so, and cites `SurfaceParsers.moduleNameTok` for why the upper-case module path is exact rather than a guess.  Verified with three hand-built interfaces read through `G1Compare`: `(\|Layout.Report.Relation.cutoff\|)` **accepted**, `(\|Field.Count\|)` **accepted**, `(\|Mod.foo.bar\|)` **rejected** at the `.` after `foo` |
| **R-5** | nit | The corpus fixture leaks a ~3.5 MB temp tree per `core/test` run and never deletes it | **Deleted.**  A reference-counted `releaseCorpus` in a `finally` in each of the two properties that share the tree (either may run last), plus a `sweepStaleCorpusTrees` at build time that removes `ermine-ei-corpus*` directories older than an hour — the age guard so a concurrent run's tree is never touched.  Property 1's own (kilobyte) workspace is deleted in a `finally` too, so the suite now leaks nothing.  Measured: 0 `ermine-ei-corpus*` and 0 `ermine-row*` directories left after three consecutive runs |
| **R-6** | nit | (a) the ticket gives `fieldStatementP`'s `identTok` as the reason for BOTH the abnormal label (N6/N7) and the operator label (N8); it is N8's only.  (b) the reviewer's timing bands sit ~0.5 s above the report's on the pre side | **Both corrected.**  (a) The ticket and §2's N6/N7/N8 rows now give the two mechanisms separately: the SOURCE row grammar refuses a literal ident (N6/N7) — noting that `TypeNameParsers.ident` is `super.ident \| literalIdent`, so the interface grammar alone would look permissive — while `fieldStatementP` refuses to DECLARE an operator-named label (N8).  (b) §6 now carries the reviewer's numbers beside mine and says to read the gap, not the digits |

### Gates re-run after the fix round

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | clean, exit 0; still only the pre-existing `TypeParsers.scala:76` pattern warning |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**, `skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; 3 properties green |
| `tracker/tools/corpus-run.sh --batch` | **85 LOADED / 69 REJECTED / 0 UNKNOWN**, 154 total |
| `tracker/tools/repl-smoke.sh` | all PASS — aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5 |
| `tracker/tools/lsp-smoke.sh` | **PASS lsp (185 checks)** |
| `tracker/tools/g1-validate.sh` | **9/9**, no drift from `tracker/g1-baseline`, baseline not re-cut |
| corpus double run, interfaces ON | **0 of 241 rewritten** on the second run; warm wall 24.14 s, inside the post-fix band |
| `TestInterfaceConcreteRow` alone, 3× | **3/3 green each time**, 80.7 / 80.3 / 80.2 s, `196 of 245 interfaces re-print byte-identically` on all three, 0 temp trees left |

`sbt core/test` in full was NOT re-run in the fix round: the changes are one parser `filter`, one
alpha-equivalence case and temp-tree deletion, the three properties are green three times alone, and
the suite is the intermittent gate of R-1 — a 23-minute run whose verdict is one-in-two would add
noise rather than evidence.  The reviewer's two full runs (943 total, one 942/1-error and one
943/943, the new suite green in both) stand as the record.

### One working-tree hazard, caught and repaired

`TypeParsers.scala` is a **CRLF** file (319 of 319 lines in `HEAD`).  Editing it through Python's text
IO rewrote every line ending, so `git diff --numstat` read `356 / 319` — a whole-file rewrite hiding a
one-line change.  The endings were restored byte-wise (`b.replace(b"\n", b"\r\n")` on the binary
content) and the diff is now **38 insertions / 1 deletion**, which is the change and nothing else.
The compile, `TestLoopTrace` (720/720) and the corpus batch (85/69/0) were re-run afterwards on the
restored file, and `TestInterfaceConcreteRow` is green on it (3/3, `196 of 245`).  Whoever edits that
file next: edit it byte-wise.

Every `.ei` this round caused is deleted; the 143 checked-in under `tracker/g1-*` are untouched;
`tracker/lean/` untouched; nothing committed.
