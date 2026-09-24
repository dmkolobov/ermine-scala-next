# ScalaCheck suites in ermine-scala: did they catch real defects? (history audit, 2026-09-17)

This is a read-only audit. Nothing was built or run, and no git state was changed. The repo is at
`/home/dmitry/research/ermine/ermine-scala` (branch `json-encode`), and `git log --all` covers 1,160 commits.

How to read the counts: each count is a number of **distinct evidence items** (one defect, one flake cause,
or one intended behaviour change). Repeat sightings of the same cause are not counted again. When two
suites went red on the same defect, the count goes to the suite the source names as the catcher, and the
other suite is listed as "co-detected, not counted". `(u)` means the count includes that many `UNSURE:` items.

**Headline.** Across 53 suites I found **8 REAL-DEFECT catches** in **6 suites**. Two of the 8 are UNSURE.
In the same period there were **15 WRITTEN-WITH-FIX** regression tests and **8 SELF-DEFECT** findings.
**21 suites** have zero in every column. **44 suites** have no REAL-DEFECT and no GATE-DEFECT.

## 1. All suites

Property count = the number of `property(` occurrences in the object's text (for `TestErmineModules`, in
the traits it mixes in). This is a static count, not the number registered at run time: for example,
`TestConstraints."disjunction sound"` only registers under `-Dermine.test.disjunction=true`. First-commit
dates for the 2015 suites come from the export commit `eca45f57`. `git log` prints no date for that
commit because its author line is malformed, but its raw timestamp 1430421113 is 2015-04-30.

| suite object | Properties name | file | property count | first commit date | REAL-DEFECT | GATE-DEFECT | SELF-DEFECT | EXPECTED-CHANGE | FLAKE | WRITTEN-WITH-FIX |
|---|---|---|---|---|---|---|---|---|---|---|
| TestAmalgamation | SQL relation optimizer | core/src/test/scala/com/clarifi/reporting/backends/TestAmalgamation.scala | 3 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestLoopTrace | loop model trace | core/src/test/scala/com/clarifi/reporting/ermine/loopmodel/TestLoopTrace.scala | 3 | 2026-09-04 | 0 | 0 | 1 | 0 | 0 | 1 |
| TestFlatteners | Flatteners | core/src/test/scala/com/clarifi/reporting/flatteners/TestFlatteners.scala | 25 (incl. `include`d property classes) | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestOptimizer | SQL relation optimizer | core/src/test/scala/com/clarifi/reporting/relational/TestOptimizer.scala | 2 | 2015-04-30 | 0 | 0 | 0 | 1 | 0 | 0 |
| TestProcessSymbols | process symbol processes | core/src/test/scala/com/clarifi/reporting/relational/TestProcessSymbols.scala | 7 | 2015-05-13 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestSqlEmitters | emitSql | core/src/test/scala/com/clarifi/reporting/sql/TestSqlEmitters.scala | 5 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestAccess | relational capability testing | core/src/test/scala/com/clarifi/reporting/TestAccess.scala | 10 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestConstraints | Constraints | core/src/test/scala/com/clarifi/reporting/TestConstraints.scala | 19 | 2015-04-30 | 0 | 0 | 1 | 0 | 0 | 0 |
| TestLenses | Lenses | core/src/test/scala/com/clarifi/reporting/TestLenses.scala | 4 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestRelations | relation ADTs | core/src/test/scala/com/clarifi/reporting/TestRelations.scala | 9 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestErmineRelations | Ermine relations | core/src/test/scala/com/clarifi/reporting/TestRelations.scala | 7 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestRTag | PrimTs, PrimExprs, Reflexivity | core/src/test/scala/com/clarifi/reporting/TestRTag.scala | 18 | 2015-04-30 | 1 | 0 | 0 | 0 | 0 | 1 |
| TestGraph | graph types | core/src/test/scala/com/clarifi/reporting/util/TestGraph.scala | 24 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestStreamTUtils | StreamT utilities | core/src/test/scala/com/clarifi/reporting/util/TestStreamTUtils.scala | 9 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestKeyValueTabular | tables w/dynamic schema | core/src/test/scala/com/clarifi/reporting/writers/TestKeyValueTabular.scala | 4 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestLegend | Legends & presentations | core/src/test/scala/com/clarifi/reporting/writers/TestLegend.scala | 17 | 2015-04-30 | 0 | 0 | 0 | 0 | 1 | 0 |
| TestErmineLegends | Ermine legends | core/src/test/scala/com/clarifi/reporting/writers/TestLegend.scala | 1 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestMarkdown | Markdown | core/src/test/scala/com/clarifi/reporting/writers/TestMarkdown.scala | 4 | 2015-04-30 | 0 | 0 | 0 | 0 | 1 | 0 |
| TestWriters | writer API | core/src/test/scala/com/clarifi/reporting/writers/TestWriters.scala | 2 | 2015-04-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestDateAndScan | Date, dateDiff and Layout.Scan (F3) | scalacheck-binding/src/main/scala/TestDateAndScan.scala | 13 | 2026-09-08 | 0 | 1 | 0 | 0 | 1 | 1 |
| TestDecode | Ermine JSON Decode | scalacheck-binding/src/main/scala/TestDecode.scala | 13 | 2026-09-16 | 0 | 0 | 1 | 0 | 1 | 0 |
| TestDoc | JSON document writer (J3b) | scalacheck-binding/src/main/scala/TestDoc.scala | 20 | 2026-09-16 | 0 | 1 (1u) | 0 | 1 | 1 (1u) | 0 |
| TestEditorBuffers | Editor buffers 5.3 | scalacheck-binding/src/main/scala/TestEditorBuffers.scala | 12 | 2026-08-31 | 0 | 0 | 0 | 0 | 0 | 1 |
| TestErmine | Ermine | scalacheck-binding/src/main/scala/TestErmine.scala | 30 | 2015-04-30 | 1 | 1 | 0 | 0 | 0 | 0 |
| TestErmineModules | Ermine library | scalacheck-binding/src/main/scala/TestErmine.scala | 3 (via ErmineModulesProperties) | 2015-04-30 | 1 (1u) | 0 | 0 | 0 | 0 | 0 |
| TestInMemoryScan | in-memory scan paths (A1b) | scalacheck-binding/src/main/scala/TestInMemoryScan.scala | 5 | 2026-09-08 | 0 | 0 | 0 | 0 | 0 | 1 |
| TestInterfaceConcreteRow | Interface concrete row | scalacheck-binding/src/main/scala/TestInterfaceConcreteRow.scala | 3 | 2026-09-09 | 0 | 0 | 0 | 0 | 0 | 1 |
| TestInterfaceKey | Interface key | scalacheck-binding/src/main/scala/TestInterfaceKey.scala | 2 | 2026-09-09 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestInterfaceRoundTrip | Interface round-trip | scalacheck-binding/src/main/scala/TestInterfaceRoundTrip.scala | 1 | 2026-08-30 | 1 (1u) | 1 | 0 | 0 | 1 | 0 |
| TestJson | Ermine JSON | scalacheck-binding/src/main/scala/TestJson.scala | 28 | 2026-09-14 | 0 | 0 | 0 | 0 | 1 | 0 |
| TestLetSignatures | Ermine let signatures | scalacheck-binding/src/main/scala/TestLetSignatures.scala | 10 | 2026-09-11 | 0 | 0 | 0 | 1 | 0 | 1 |
| TestLower | Lower 3.4a | scalacheck-binding/src/main/scala/TestLower.scala | 28 | 2026-08-30 | 0 | 1 | 0 | 0 | 0 | 0 |
| TestNamedFields | Ermine named constructor fields | scalacheck-binding/src/main/scala/TestNamedFields.scala | 16 | 2026-09-14 | 0 | 0 | 0 | 0 | 0 | 1 |
| TestNewPipeline | NewPipeline 4.1c | scalacheck-binding/src/main/scala/TestNewPipeline.scala | 2 | 2026-08-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestQuickFix | Quick fixes 6.6 | scalacheck-binding/src/main/scala/TestQuickFix.scala | 18 | 2026-09-10 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestReassoc | Reassoc 3.3 | scalacheck-binding/src/main/scala/TestReassoc.scala | 13 | 2026-08-30 | 0 | 0 | 0 | 1 | 0 | 0 |
| TestRecordPrims | record primitives forced (A1) | scalacheck-binding/src/main/scala/TestRecordPrims.scala | 8 | 2026-09-07 | 0 | 0 | 0 | 0 | 0 | 1 |
| TestRenamer | Renamer 3.2a | scalacheck-binding/src/main/scala/TestRenamer.scala | 34 | 2026-08-30 | 1 | 0 | 0 | 0 | 0 | 0 |
| TestReplDifferential | REPL eval goldens | scalacheck-binding/src/main/scala/TestReplDifferential.scala | 1 | 2026-08-30 | 0 | 0 | 0 | 1 | 0 | 1 |
| TestRowRefusals | unsatisfiable row programs (S2) | scalacheck-binding/src/main/scala/TestRowRefusals.scala | 1 | 2026-09-16 | 0 | 0 | 2 (1u) | 0 | 0 | 0 |
| TestRunner | JSON document runner (J3c) | scalacheck-binding/src/main/scala/TestRunner.scala | 17 | 2026-09-16 | 0 | 0 | 3 | 0 | 1 | 1 |
| TestSchema | Ermine JSON Schema | scalacheck-binding/src/main/scala/TestSchema.scala | 27 | 2026-09-14 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestScopes | Ermine scoping | scalacheck-binding/src/main/scala/TestScopes.scala | 30 | 2026-08-30 | 0 | 0 | 0 | 1 | 1 | 1 |
| TestSigEntailDiff | Ermine signature entailment (differential) | scalacheck-binding/src/main/scala/TestSigEntailDiff.scala | 8 | 2026-09-11 | 0 | 0 | 0 | 0 | 0 | 1 |
| TestSigEntail | Ermine signature entailment | scalacheck-binding/src/main/scala/TestSigEntail.scala | 13 | 2026-09-10 | 0 | 0 | 0 | 1 | 0 | 0 |
| TestStage1Pins | Ermine stage1 pins | scalacheck-binding/src/main/scala/TestStage1Pins.scala | 34 | 2026-08-30 | 3 | 0 | 0 | 2 | 1 | 0 |
| TestStatementExtents | Statement extents | scalacheck-binding/src/main/scala/TestStatementExtents.scala | 4 | 2026-08-31 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestSurfaceCache | Surface cache | scalacheck-binding/src/main/scala/TestSurfaceCache.scala | 5 | 2026-09-11 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestSurfaceParsers | Surface parser 2.3a | scalacheck-binding/src/main/scala/TestSurfaceParsers.scala | 12 | 2026-08-30 | 0 | 0 | 0 | 2 | 0 | 0 |
| TestSurface | Surface AST | scalacheck-binding/src/main/scala/TestSurface.scala | 3 | 2026-08-30 | 0 | 0 | 0 | 0 | 0 | 0 |
| TestTolerantCheck | Tolerant check | scalacheck-binding/src/main/scala/TestTolerantCheck.scala | 58 | 2026-08-31 | 0 | 0 | 0 | 0 | 1 | 2 |
| TestTolerantRead | Tolerant read | scalacheck-binding/src/main/scala/TestTolerantRead.scala | 11 | 2026-08-31 | 0 | 0 | 0 | 1 | 2 | 0 |
| TestWidgets | widget prop types (J3d) | scalacheck-binding/src/main/scala/TestWidgets.scala | 6 | 2026-09-16 | 0 | 0 | 0 | 0 | 0 | 0 |
| **total (53 suites)** | | | | | **8 (2u)** | **5 (1u)** | **8 (1u)** | **12** | **13 (1u)** | **15** |

Not counted in any suite (the attribution could not be made): 1 REAL-DEFECT (2015, `b1453b19`) and
2 GATE-DEFECT (2026, `be085509`, `1b4bf66c`). They are listed at the end of §2.

## 2. Evidence rows (every non-zero cell)

Quotes are verbatim. Where a source wraps lines, the wrapped lines are joined with one space. The 8-char
SHA is the fix commit.

### REAL-DEFECT (8, of which 2 UNSURE)

| suite | class | fix SHA | date | defect | verbatim quote | source |
|---|---|---|---|---|---|---|
| TestRTag | REAL-DEFECT | fb3537ca | 2015-08-04 | `5ad56634` (2015-07-09, "Canonicalize PrimT cases") made `StringT` a `final class` with no `equals`, so two equal StringTs compared unequal. TestRTag predates it (2015-04-30). | "Make StringTs java-equal again.  Fixes TestRTag." | commit fb3537ca subject |
| TestErmine | REAL-DEFECT | 5ba81767 | 2026-08-30 | Scala 3 port: case-class companions no longer extend `FunctionN`, so 30+ foreign bindings (Op, Format, Chart, Axis, Windowed) failed at run time. Co-detected by TestErmineLegends ("presentation coercion"), not counted there. | "A real Scala 3 regression the REPL smoke test missed." / "Fixes Ermine.Ops run and Ermine legends.presentation coercion." | tracker/06-tests.md:59; commit 5ba81767 body |
| TestStage1Pins | REAL-DEFECT | faa5769e | 2026-08-31 | The new pipeline's 4.2 pairing rewrite silently merged interleaved equations of one name. The pin "interleaved equations of one name are refused" dates from 6d831203 (2026-08-30). | "interleaved equations of one name were silently MERGED by the 4.2 pairing rewrite — now refused (gatherBindings parity, caught by the Stage-1 pin)" | tracker/LSP-ROADMAP.md:3149-3151 |
| TestStage1Pins | REAL-DEFECT | ba6429c0 | 2026-08-31 | The surface parser could not open a term chain with a prefix operator (found when the pins were converted to the pipeline statement path) | "Real fixes shaken out: (1) term chains can OPEN with prefix operators — operand tried first, so ?[w] keeps its lexeme (the fused-only paren-stacked-prefix pin exposed the gap" | tracker/LSP-ROADMAP.md:3161-3164 |
| TestStage1Pins | REAL-DEFECT | ba6429c0 | 2026-08-31 | The split pipeline silently dropped the members of `class` statements that have a body or context. The pre-existing `failsMatching("class Frob a where ...")` pins expected a refusal. | "(2) class statements with a body or context REFUSE at assemble (the fused type processing died with undefined type; the split pipeline was silently IGNORING bodies)" | tracker/LSP-ROADMAP.md:3166-3168; the pins' diff in ba6429c0 |
| TestRenamer | REAL-DEFECT | 8f16f913 | 2026-09-16 | The LSP symbol tree emitted a record-style constructor's field selectors as overlapping siblings (introduced by 36eaf0dc, 2026-09-14). It showed once Layout/Doc.e declared a record-style data. The property dates from 6.4 (d6d728e6, 2026-09-10). | "The landing's full `core/test` on 0a558d68 falsified `Renamer 3.2a.6.4 corpus: siblings are sorted, and no two of them straddle` with 7 straddling pairs" | tracker/json-stage3/report-J3b.md:73-74 |
| TestErmineModules | REAL-DEFECT | 93c9d1bb | 2026-09-11 | Example `core/examples/SoftRelation.e` built a drilldown row with `dt` twice. **UNSURE:** the defect is in example code, not the product; an intended signature change (honest `cons_Bracket`) exposed it; the corpus sweep rejected it too. Co-detected by TestTolerantRead, not counted there. | "Caught by `sbt core/testOnly *TestErmine*`, not by the corpus sweep" / "`TestErmineModules.all interesting examples load` and `TestTolerantRead.strict and tolerant agree` both failed" | tracker/loopmodel/SIG-3b-CORRECTIONS.md:111, :331-333 |
| TestInterfaceRoundTrip | REAL-DEFECT | be085509 | 2026-08-31 | Session.scala: the process-global depCache handed out Dep closures that had baked in the creating session's `typeCheck`/`useInterface`. **UNSURE:** the only red was an intermittent cross-suite failure, and no product path (two differently-configured sessions in one JVM) was demonstrated. A different flake in the same property is still open (E12, below). | "Dep closures no longer bake their creation session s typeCheck/useInterface — the gate moved to make() with the live session, ending cross-suite dep-cache poisoning (the Interface round-trip flake)" | tracker/LSP-ROADMAP.md:3127-3131; commit be085509 Session.scala diff |
| *(unattributed, not counted)* | REAL-DEFECT | b1453b19 | 2015-07-21 | `e0551996` (2015-07-14) cached `DoubleExpr` zero and one as nullable only, so `DoubleExpr(false, 0.0)` returned a nullable expression. The commit only says "Fixed tests." and also fixes RelationGens compilation. **UNSURE** which suite went red: TestRTag, TestRelations and TestLegend all use `RelationGens`. | "Fixed tests." | commit b1453b19 (PrimExpr.scala: `sZero`/`nZero` split) |

### GATE-DEFECT (5 counted, of which 1 UNSURE; 2 unattributed)

| suite | class | fix SHA | date | defect | verbatim quote | source |
|---|---|---|---|---|---|---|
| TestLower | GATE-DEFECT | edb6434f | 2026-09-09 | TestInterfaceKey flipped `ermine.loadInSeries` for the whole JVM, so a concurrent TestLower load failed with `Module not found: 'Test'` about one full run in two | "The F4-era intermittence (942+1 error one run in two, "Module not found: 'Test'") was TestInterfaceKey setting ermine.loadInSeries=true with System.setProperty" | commit edb6434f body; detection tracker/loopmodel/F4-REVIEW.md:33 |
| TestInterfaceRoundTrip | GATE-DEFECT | 53216547 | 2026-09-09 | TestInterfaceKey's first draft (inside stage S5, never committed in that form) set JVM-wide system properties that SessionEnv reads as defaults | "the flip reached `TestInterfaceRoundTrip`'s session and made it fail (940 total, 1 failed)" | tracker/loopmodel/S5-HYGIENE.md:433-434 |
| TestErmine | GATE-DEFECT | 21a331a2 | 2026-08-31 | ErmineFixture's baseEnv writeback captured a session holding the dynamic Test module, so later properties "loaded" ill-kinded modules without loading them. This also made some TestErmine properties vacuous. | "The conversion exposed a vicious fixture bug: kindAfter runs loadStatements" / "ill-kinded modules 'loaded' by not loading at all" | tracker/LSP-ROADMAP.md:3183-3188; commit 21a331a2 "writeback-poisoning root fix" |
| TestDoc | GATE-DEFECT | 17cdcbd1 | 2026-09-16 | J2a/J3b merge gap: TestSchema's widened generator drew modules that were missing from `TestDoc.dImps`. **UNSURE:** the defective import list sits in TestDoc.scala itself. | "`(d)` failed 13 of 80 cases with "undefined type"." / "This is a **J2a/J3b merge gap** that the orchestrator's merge did not surface because neither stage re-ran the other's suite." | tracker/json-stage3/report-J3c.md:179 |
| TestDateAndScan | GATE-DEFECT | dcd367de (scala3-migration); 36c2dcf9 (json-encode) | 2026-09-16 | The harness's `no(...)` returned "passed" rather than "proved", so ScalaCheck ran a slow refutation 100 times and wedged three landing runs. It was first misdiagnosed as a checker cliff and quarantined (3374deaf). | "what ran for twenty minutes was ScalaCheck evaluating a *passed* refutation a hundred times, fixed by `ErmineFixture.rejects`" | tracker/GATE-POLICY.md:61-62 |
| *(unattributed, not counted)* | GATE-DEFECT | be085509 | 2026-08-31 | Test threads under the ScalaCheck pool shared one ErmineFixture `Supply` and raced. The source does not say which suites the 7+ sightings were in. | "the recurring eval:unbound flake class, 7+ sightings, now root-caused" | tracker/LSP-ROADMAP.md:3134-3135 |
| *(unattributed, not counted)* | GATE-DEFECT | 1b4bf66c | 2026-08-30 | Tests set the process-global `-Dermine.pipeline` property, so concurrently running properties saw each other's setting. The fix made the switch session-level; the three suites are not named. | "concurrently-running test properties saw each other's flag (three suites falsified under the full run, green in isolation — the concurrency-flake protocol caught it)" | tracker/LSP-ROADMAP.md:2952-2954 |

### SELF-DEFECT (8 counted, of which 1 UNSURE)

| suite | class | fix SHA | date | defect | verbatim quote | source |
|---|---|---|---|---|---|---|
| TestConstraints | SELF-DEFECT | none (quarantined 1c8ff562, 2026-09-08) | since 2015-04-30 | The `disjunction sound` generator never satisfies its own precondition, so the property has never run a case | "generator starvation (0 passed / 501 discarded, every run on record)" / "Every generated case is discarded, so the property never runs." | tracker/GATE-POLICY.md:41; tracker/06-tests.md:94 |
| TestLoopTrace | SELF-DEFECT | 4aeb4cfc (creation commit, after review) | 2026-09-04 | A failure on the compiler side of the comparison was reported as a PASS (L4 review F1) | "the property turns a failure of the compiler side into a PASS." | tracker/loopmodel/L4-REVIEW.md:26 |
| TestRowRefusals | SELF-DEFECT | dcd367de | 2026-09-16 | The generator checked only `startsWith("refused: ")`, so a module refused for the wrong reason read green (S2 review F-1, same stage) | "the generator asserted `startsWith("refused: ")` and never "refused by THIS check", so a machine-generated module that died for the wrong reason would have read green" | tracker/satterm/SUBSUME-STAGE2.md:594 |
| TestRowRefusals | SELF-DEFECT | fbd6826a (backport-2.11) | 2026-09-16 | 2.11 port: under scalacheck 1.11.3, an empty sample made `Prop.all()` report proved. This was latent (it could not fire yet) and was fixed in the port. **UNSURE:** I took the fix SHA from the review's F-1 "YES" and from memory notes; I did not diff it. | "**An empty sample is therefore reported as `OK, proved property` while asserting nothing at all.**" | backport-2.11:backport/SUBSUME-2.11-REVIEW.md:36-37, :341 |
| TestDecode | SELF-DEFECT | 2c371bd6 | 2026-09-16 | The `(a2)` equivalence missed a raw `Some(JNull)`, a false red while the decoder was correct (J2a verification) | "Found while verifying: (a2)'s equivalence had a hole" / "The decoder was right; the comparison was not." | tracker/json-stage3/report-J2a.md:160-164 |
| TestRunner | SELF-DEFECT | 84af8a10 | 2026-09-16 | Property `(a)` built its request with argonaut's `nospaces`, which scrambles key order: a false red once Spread Json landed (seen first on the 2.11 port) | "the order-sensitive comparison in (a) read the printer's scrambling as a round-trip failure.  Test only; the runner, decoder and encoder are correct." | commit 84af8a10 body |
| TestRunner | SELF-DEFECT | 2eee426f | 2026-09-16 | The `(c-routes)` pin compared HEAD /health's length with a body that changes as modules load | "a GET and a later HEAD legitimately saw different bodies (1214 vs 1227 bytes) at the J3c landing run." | commit 2eee426f body |
| TestRunner | SELF-DEFECT | d1d92721 | 2026-09-16 | A suite-lifetime server leaked non-daemon threads and a listening socket into the shared core/test JVM | "The suite-lifetime lazy val leaked a non-daemon dispatcher, up to eight non-daemon workers and a listening socket into the shared core/test JVM" | commit d1d92721 body |

### EXPECTED-CHANGE (12)

| suite | class | fix SHA | date | defect / change | verbatim quote | source |
|---|---|---|---|---|---|---|
| TestOptimizer | EXPECTED-CHANGE | d25abb49 | 2015-05-22 | The optimizer became less aggressive with literals, and the expected projections were updated | "Fixed the optimizer tests now that we're less aggressive with literals" | commit d25abb49 subject |
| TestSurfaceParsers | EXPECTED-CHANGE | 2014f070 | 2026-09-01 | New example corpora; the hard-coded file count was bumped | "The corpus file count moves 180 -> 271." | commit 2014f070 body |
| TestSurfaceParsers | EXPECTED-CHANGE | 8a6a27a0 | 2026-09-07 | Example groups E1-E4 grew the corpus; the count was made derived, with a floor | "`TestSurfaceParsers 2.3a` — `Expected 271 but got 315`" | tracker/loopmodel/E1-EXAMPLES.md:413 |
| TestTolerantRead | EXPECTED-CHANGE | 2014f070 | 2026-09-01 | A corpus of deliberately-bad code (`shouldfail/`, `incomplete/`) was excluded from the sweep | "a corpus of deliberately-bad code breaks it, so `shouldfail/`, `shouldfail-controls/` and `incomplete/` are excluded from that sweep" | commit 2014f070 body |
| TestStage1Pins | EXPECTED-CHANGE | ba6429c0 | 2026-08-31 | Refusal messages and positions moved per Decision f | "Moved-refusal message updates per Decision f" | tracker/LSP-ROADMAP.md:3174-3175 |
| TestStage1Pins | EXPECTED-CHANGE | 32720d6a | 2026-08-31 | D6: a fixity declaration now governs its whole scope | "Four pins flipped to the positive semantics (two in TestStage1Pins, two in TestReassoc)." | tracker/LSP-ROADMAP.md:3220-3222 |
| TestReassoc | EXPECTED-CHANGE | 32720d6a | 2026-08-31 | Same D6 flip | "Four pins flipped to the positive semantics (two in TestStage1Pins, two in TestReassoc)." | tracker/LSP-ROADMAP.md:3220-3222 |
| TestScopes | EXPECTED-CHANGE | a232222d | 2026-08-30 | Alias refusals flipped to positive Haskell scoping | "Stage 4.4: alias-refusal flips — positive Haskell scoping under the new pipeline" | commit a232222d subject |
| TestReplDifferential | EXPECTED-CHANGE | ba6429c0 | 2026-08-31 | The chain-start parse change updated two goldens | "Two REPL goldens updated for the chain-start change (still refusals, same positions, better messages)." | tracker/LSP-ROADMAP.md:3177-3178 |
| TestSigEntail | EXPECTED-CHANGE | b7dd07cc | 2026-09-11 | The signature check shipped, so the pins of the known hole flipped | "TestSigEntail's KNOWN HOLE properties are no(...) with the message (13/13)." | commit b7dd07cc body |
| TestLetSignatures | EXPECTED-CHANGE | e61cc402 | 2026-09-11 | Signature entailment landed at its default, so a pin became a rejection | "the let-bound too-weak-context pin in TestLetSignatures becomes a rejection, as sig03 is." | commit e61cc402 body |
| TestDoc | EXPECTED-CHANGE | 62351477 | 2026-09-16 | The `(b-sql)` measurement of the GUID bug moved when J3c fixed that bug | "`(b-sql)` asserted `badNulls == List("UUID")` — a *measurement* of the GUID bug. My fix makes a nullable GUID carry, so the measurement moved" | tracker/json-stage3/report-J3c.md:180 |

### FLAKE (13 counted, of which 1 UNSURE)

| suite | class | fix SHA | date | defect | verbatim quote | source |
|---|---|---|---|---|---|---|
| TestLegend | FLAKE | none (ticket E13 open) | first recorded 2026-09-01/02; sightings 2026-09-04, 09-07, 09-11, 09-16 | `"extra args are ignored"`: seed-dependent date-range formatting | "Expected 5/23/12–1/20/47 but got 5/23/12–1/22/21" | tracker/loopmodel/S2-REVIEW.md:555; tracker/ROW-CONSTRAINT-STATE.md:1415-1416; tracker/GATE-POLICY.md:48 |
| TestInterfaceRoundTrip | FLAKE | none (ticket E12 open) | sightings 2026-09-06 (A1), 09-08 (F3), 09-11 (7.1b, G4) | Another suite repopulates the process-global depCache between this property's clear and its warm load | "fails roughly one full run in ten when ANOTHER SUITE in the same JVM repopulates the process-global `Session.depCache`" | tracker/GATE-POLICY.md:43-45 |
| TestTolerantCheck | FLAKE | none (E11b parked by the user) | 2026-09-16 | The E11a ceiling-3 pin: the published constraint SET varies from run to run on an unchanged tree | "seen at the J3b landing as "SET class grew past its ceiling 3: (reportFor,4)", green on re-run 3/3" | tracker/GATE-POLICY.md:52-54 |
| TestMarkdown | FLAKE | none | 2026-08-30 | Unexplained; the source treats it as the early cross-suite concurrency flake | "run also errored TestMarkdown; gone on re-run and alone — flake, watching." | tracker/LSP-ROADMAP.md:2507-2508 |
| TestStage1Pins | FLAKE | none recorded (UNSURE: possibly the Supply race fixed in be085509) | 2026-08-30 | Exception-flavour red at the 1.3b full run | "the 1.3b commit's full-suite run showed 2 extra reds (a stage1 pin + a TestScopes property, exception flavor); clean 795/796 on immediate re-run" | tracker/LSP-ROADMAP.md:2645-2647 |
| TestScopes | FLAKE | same as above | 2026-08-30 | Same 1.3b event | same quote | tracker/LSP-ROADMAP.md:2645-2647 |
| TestJson | FLAKE | 2c371bd6 | 2026-09-16 | Properties declared the same type names into the process-global, last-writer-wins `DataConDecl` map | "Found while verifying: `TestJson` had a pre-existing cross-property race" | tracker/json-stage3/report-J2a.md:149 |
| TestDecode | FLAKE | 2c371bd6 | 2026-09-16 | `(e2)` re-parsed at a measured stack depth that swings with JIT state, raising StackOverflowError about 1 run in 15 (J2a review) | "`TestDecode.(e2)` is flaky and will intermittently redden the gate" | tracker/json-stage3/review-J2a.md:118 |
| TestTolerantRead | FLAKE | c7aa9c92 | 2026-08-31 | The corpus sweep inherited modules that concurrently running pins had written back into the shared fixture baseEnv | "ROOT-CAUSED A NEW FLAKE rather than re-running it: the corpus sweep failed about one full-suite run in three with "159 of 180 read clean"" | tracker/LSP-ROADMAP.md:3356-3358 |
| TestTolerantRead | FLAKE | none (environmental) | 2026-09-07 | Concurrent example-writing agents created or deleted corpus files mid-run | "caused by another agent deleting `core/examples/Wide/` mid-run" | tracker/loopmodel/E2-REVIEW.md:676-678; tracker/loopmodel/E1-EXAMPLES.md:415 |
| TestRunner | FLAKE | 36c2dcf9 | 2026-09-16 | `(iso)`'s 180 s deadline fired while the property queued on `ErmineFixture.literalLock` behind library-scale loads | "a fixture type-check after a Runner boot: did not finish, 180004 ms" | tracker/satterm/SUBSUME-M2.md:175-178 |
| TestDateAndScan | FLAKE | dcd367de (inside stage S2) | 2026-09-16 | The new B1 deadline pin queued on the same lock | "Two of three runs then went red at exactly 60,000 ms with nothing wrong." | tracker/satterm/SUBSUME-STAGE2.md:47-50 |
| TestDoc | FLAKE | none | 2026-09-16 | **UNSURE:** `(b-sql)` lost the Timestamp column type once under load and never reproduced | "I also saw `(b-sql)` report `column types lost: List(Timestamp)` **once**, in the first heavily loaded six-suite run, and never again in four later runs" | tracker/json-stage3/report-J3c.md:182 |

### WRITTEN-WITH-FIX (15): regression tests, not catches

| suite | class | fix SHA | date | defect fixed | verbatim quote | source |
|---|---|---|---|---|---|---|
| TestRTag | WRITTEN-WITH-FIX | 79cd6787 (dup 6678b420) | 2015-08-26 | `StringT.equals` threw MatchError on non-StringT; the fix added `case _ => false` plus `"StringT equal is total"` | "StringT equality, and PrimT equality/matching tests." | commit 79cd6787 |
| TestScopes | WRITTEN-WITH-FIX | 61432b0b | 2026-08-30 | let binders did not shadow imports or restore scope | "Tests: TestScopes.scala (28 properties; the shadow/restore half fails on the pre-fix parser)" | commit 61432b0b body |
| TestReplDifferential | WRITTEN-WITH-FIX | d37814ed | 2026-08-30 | Free variables reached eval as PANICs on the new REPL path | "eval as PANICs (caught by the new TestReplDifferential corpus, 21 expressions evaluated through BOTH paths" | tracker/LSP-ROADMAP.md:3102-3103 |
| TestEditorBuffers | WRITTEN-WITH-FIX | 4a8900ff | 2026-08-31 | Decorating SourceFile.toString broke diagnostic positions and definition locations | "ONE TRAP FOUND THE HARD WAY: SourceFile.toString is the fileName" / "TestEditorBuffers pins it now." | tracker/LSP-ROADMAP.md:3391-3395 |
| TestLoopTrace | WRITTEN-WITH-FIX | b0c97b99 | 2026-09-04 | makeEmpty self-propagation panic, found by the Lean model's witness hunt (not by this suite); the PANIC3 seed was added | "TestLoopTrace 708/708 with PANIC3 in the population" | commit b0c97b99 body |
| TestRecordPrims | WRITTEN-WITH-FIX | fac46775 | 2026-09-07 | `record#` returned a 2.13 MapView, so eight consumers panicked | "TestRecordPrims (8 properties, scalacheck-binding) forces those values in core/test and fails 8 of 8 on the pre-fix build." | commit fac46775 body |
| TestInMemoryScan | WRITTEN-WITH-FIX | 6fc77fac | 2026-09-08 | MapView equality in pivot, hashJoin and sort (a 2.13 migration defect) | "TestInMemoryScan drives all three (negative control 4/5 falsified)." | commit 6fc77fac body |
| TestDateAndScan | WRITTEN-WITH-FIX | 6fc77fac | 2026-09-08 | Date accessors used the default time zone | "TestDateAndScan probes under an explicit non-UTC zone via one locked, restoring helper (no global default mutation); 12/12 pass, 5/12 fail with A3 reverted." | commit 6fc77fac body |
| TestInterfaceConcreteRow | WRITTEN-WITH-FIX | f9266adb | 2026-09-09 | A published concrete row never read back from `.ei` (ticket E1) | "Tests (TestInterfaceConcreteRow, all RED on the pre-fix compiler)" | commit f9266adb body |
| TestLetSignatures | WRITTEN-WITH-FIX | 75253148 | 2026-09-11 | let-bound signatures were ignored, a regression since faa5769e that no suite caught | "Pins: TestLetSignatures (restrict in all four shapes; honest polymorphic let and where accepted" | commit 75253148 body |
| TestSigEntailDiff | WRITTEN-WITH-FIX | b7dd07cc | 2026-09-11 | Closure fixpoint and empty-lhs normalisation. **UNSURE:** the source does not say whether the bugs were in the engine or in the Python oracle. | "(the S2 oracle, two bugs found by this test and fixed: closure fixpoint, empty-lhs normalisation)" | commit b7dd07cc body |
| TestTolerantCheck | WRITTEN-WITH-FIX | 9313d109 | 2026-09-13 | E11a's canonical key was name-free but the rendering was not; the property was added in the same item | "**R-1 (BLOCKING). `TestTolerantCheck`'s corpus property is red about one run in three, and the cause is a real gap in the rule" | tracker/loopmodel/E11a-REVIEW.md:21-22 |
| TestTolerantCheck | WRITTEN-WITH-FIX | 4359d644 | 2026-09-13 | E14: the 6.2 arity split could hover a type the binder does not have. The ticket cites `8a8455ce`, which does not resolve in this repo. | "LSP interstage item 6.2c (E14): a local head hovers the scheme the checker published" | commit 4359d644 subject; tracker/loopmodel/LSP-6.2c-HEADS.md:230 |
| TestNamedFields | WRITTEN-WITH-FIX | 8f16f913 | 2026-09-16 | The symbol-tree straddle (the catch is credited to TestRenamer above) | "Pinned in TestNamedFields: a well-formedness property over the suite's random record declarations" | commit 8f16f913 body |
| TestRunner | WRITTEN-WITH-FIX | 62351477 | 2026-09-16 | A NULL GUID threw an NPE, and `withDriver` had no `finally` (both measured by J3b's TestDoc, fixed in J3c) | "Property **(sql-guid)** round-trips random relations with a nullable GUID column" / "it fails with an NPE on the old code." | tracker/json-stage3/report-J3c.md:172 |

### UNSURE, not counted in any column

- **TestErmineModules, 508021b8 (2019-05-15):** the red was silenced, not fixed. The quote: "Comment out box and whisker example so tests work. - TODO: make it actually work?" (commit body). The cause is not identified.
- **TestConstraints `"join example"`:** it went red under candidate solver variants that were never adopted. The quote: "| `Constraints.join example` | passes | **passes** | **FALSIFIED** |" under `nongen`, and "no termination" under `+disj` (tracker/TICKET-row-constraint-decision.md:1014, :1062, 2026-09-01/02). There was no fix, because the variant was rejected, and the should-fail corpus refuted `nongen` independently.
- **TestLoopTrace, 74b49298 (2026-09-06, D1):** "TestLoopTrace with flags forwarded FAILS on a one-line Main.lean seed-path `--trace` bug" (tracker/LOOP-MODEL-HANDOFF.md:535-536). Both the forwarding and the Lean option were new in that stage.
- **TestDoc on json-encode-2.11 (P2):** it exposed a real SQLite Timestamp defect, but the defect was "Not fixed" and pinned as a measurement. The quote: "**Pre-existing DB-layer defect of this branch, exposed (not caused) by the JSON work; TestDoc's `(b)` is the first test to read a Timestamp column back out of SQLite.**" (json-encode-2.11:tracker/json-stage3/report-P2.md:55).
- **TestDoc at creation (J3b):** the new suite measured the pre-existing NULL-GUID NPE and the missing `withDriver` `finally` (report-J3b.md:69, :199). This is a new test finding old defects, which is neither a catch nor a fix-with-test.
- **TestStage1Pins do-anchor pin, ba6429c0:** the pin was relaxed to match worse blame placement, from "a type error inside a do block anchors on its line" to "... anchors on the bind's rhs". This is partly a fix and partly a weaker pin.
- **TestProcessSymbols (2015-05-13 to 06-26):** tests were written first against `sys.error("todo")` stubs, then implemented ("Add a medianProcess.  Median tests pass.", e4978d76). This is feature development, not a defect fix.
- **Unattributed 2015 concurrency flake:** "The first run showed TWO failures; ... I did not capture the transient's name" (tracker/PERF-ROADMAP.md:1160-1163).

## 3. Ritual / broken evidence

- **TestConstraints.** `"disjunction sound"` has been starved since the 2015 export and is quarantined: "generator starvation (0 passed / 501 discarded, every run on record)" (GATE-POLICY.md:41). The whole-loop property is commented out: "the whole-loop property `incorporateAll sound` is commented out in `TestConstraints.scala:484` — only individual rules are tested, which is the missing net." (TICKET-row-constraint-decision.md:490-492). The flagged solver branches bypass the rule properties: "`Constraints.split concrete sound` and `Constraints.resolution sound` call the rules through their SHORT signatures ... the new branches' soundness evidence is the Lean plus the gates below, not those properties." (satterm/KEYED-ROW-STAGE5.md:220-223).
- **TestLoopTrace passes when the Lean binary is absent.** "it **passes vacuously where the Lean model binary is absent** and still reports `Passed: Total 3`" (loopmodel/S3-SIMPLIFY.md:587). This is by design (`notRun` returns `Prop.proved` on skip, TestLoopTrace.scala:740-742), and it happened in practice: "`TestLoopTrace` first ran with the replay SKIPPED — no worktree had the Lean binary" (json-stage3/report-J3a.md:81).
- **Suites with one commit ever.** `git log --all` shows exactly 1 commit for TestAmalgamation and TestAccess (the 2015 export `eca45f57`). TestMarkdown has only the two export commits. 2026 suites never touched after creation: TestInMemoryScan (6fc77fac), TestQuickFix (31152510), TestSurfaceCache (f091369a), TestSurface (971010bd).
- **Duplicate suite name.** TestAmalgamation and TestOptimizer are both `Properties("SQL relation optimizer")`.
- **Twelve suites never mentioned in any tracker document:** TestAmalgamation, TestFlatteners, TestOptimizer, TestProcessSymbols, TestSqlEmitters, TestAccess, TestLenses, TestRTag, TestGraph, TestKeyValueTabular, TestWriters, TestErmineLegends (grep counts of 0).
- **TestSurfaceParsers asserted a hard-coded count.** "271 is a hard-coded count of the `.e` files under `core/src/main/resources/modules` and `core/examples`.** Adding any example breaks it." (loopmodel/E1-EXAMPLES.md:426-427). The first replacement was a tautology: "**that alone asserts nothing**" (E1-EXAMPLES.md:450).
- **TestStatementExtents names a count it does not assert.** "`TestStatementExtents`'s three "271 files" properties name the count in their titles and do not assert it" (loopmodel/E2-REVIEW.md:64-65).
- **A TestRenamer property copies the rule it should check.** "TestRenamer's new overlap property cannot catch this: it re-implements `nameLen`'s rule inline rather than calling it" (loopmodel/LSP3-6.3-REVIEW.md:101-102).
- **TestErmine properties were vacuous under the fixture bug.** "ill-kinded modules 'loaded' by not loading at all" (LSP-ROADMAP.md:3188), until 21a331a2.
- **Standing intermittents are re-run, not fixed.** E12 (TestInterfaceRoundTrip), E13 (TestLegend) and E11a (TestTolerantCheck) each fall under "exactly this property red gets ONE re-run" (GATE-POLICY.md:47, :50, :56).
- **Ports dropped or weakened checks.** A 2.11 port dropped a pin: "the Stage 1a pin the earlier port had dropped from TestJson is restored" (commit 6743002a). TestRowRefusals' empty-sample vacuity on 2.11 is in §2.
- **Regressions no suite caught** (found by other means, with a regression test added afterwards):
  - LET-1: "let-bound signatures are honoured again (regression since faa5769)" (75253148), missed for 11 days.
  - F1: "the Scala 2.13 MapView panic in pivot, Predicate.all, Record.header and five more consumers" (fac46775) and F3 A1b: "three MapView equality/hash sites from the 2.13 migration (in-memory pivot gave every column its default, hashJoin emitted nothing, sorting never grouped)" (6fc77fac). Both are Scala 3 migration defects that the pre-existing relation, writer and Ermine suites passed over.
  - The 2.11 B1 gap: "THE B1 PROGRAM IS NOT REFUSED ON THE 2.11 LINE — the F3 `dateDiff` signature was never back-ported" (backport-2.11:backport/SUBSUME-2.11.md:124).

## 4. Method and limits

**Commands run (all read-only):**
- `grep -rn 'extends Properties(' core/src/test scalacheck-binding/src` (53 objects), plus an awk count of `property(` per object.
- Per suite file: `git log --all --format='%h %ad | %s' --date=short -- <file>`, `git log --all --follow --name-status`, and `--diff-filter=A` for creation dates. `git cat-file -p eca45f57` for the undated export.
- Upstream subjects: `git log --all --until=2020-01-01 | grep -iE 'test|fail|caught|found|broke|regress|flak|red'`. I read the diffs and bodies of fb3537ca, 79cd6787, 5ad56634, b1453b19, e0551996, 6b82e47c, d25abb49, 12136817, 508021b8, 62ab0b91, 04c72c63, 98e8a780, e4978d76, 378093a3, 5ffe8db0, 58ae5549, 06e776e0, d14d9e78, ff1e2683, plus the TestSqlEmitters and TestOptimizer upstream diffs.
- 2026 commit bodies: `git log --all --since=2026-01-01` with bodies, grepped for suite names with red/caught/fail/regress/flake/exposed/found. I read the bodies of b0c97b99, 1a6fdc2e, be085509 (with Session.scala diff), 21a331a2, edb6434f, 84af8a10, d1d92721, 2eee426f, 3374deaf, 36c2dcf9, 8f16f913, bf838ce3, faa5769e, ba6429c0 (with pin diff), b7dd07cc, e61cc402, 2014f070, 6fc77fac, fac46775, 5ba81767, 75253148, 61432b0b, 806ba246, 6743002a, 9313d109. I also listed commits that touch only test files.
- Tracker docs: `grep -rn` of every `tracker/**/*.md` and the memory notes for `Test[A-Z]…` names, and separately for Properties names, filtered by red, falsified, caught, exposed, regress, flake and fail. I read the surrounding passages in GATE-POLICY.md, 06-tests.md, 05-findings.md, LSP-ROADMAP.md (baselines, iteration log 2500-3400), E1-/E2-/E3-EXAMPLES and REVIEW, S5-HYGIENE, F4-REVIEW, L4-REVIEW, S3-SIMPLIFY, E11a-REVIEW, SIG-3b-CORRECTIONS, SIG-3-REVIEW, LSP3-6.3-REVIEW, LSP4-7.2-REVIEW, LSP4-7.4-REVIEW, LOOP-MODEL-HANDOFF, D1-CHANGE, TICKET-stdlib-findings (E12, E13), TICKET-row-constraint-decision §7, ROW-CONSTRAINT-STATE, KEYED-ROW-STAGE5, SUBSUME-STAGE2 and SUBSUME-M2, and json-stage3 report/review J2a, J3b, J3c.
- Docs that exist only on other branches, read with `git show <branch>:<path>` and grepped: backport-2.11 `BACKPORT.md` and `backport/*.md`; json-encode-2.11 `tracker/json-stage3/{report,review}-P{1,2,3}.md`.

**Limits:**
- **No runs.** I executed no test. Every red is as reported in a commit message or tracker document, not reproduced.
- **2015-2019 upstream history (about 660 commits, converted from Mercurial)** has no CI logs. A red that nobody wrote into a commit subject is invisible, so upstream catches are almost certainly undercounted. Only two upstream commits tie a red to a suite: "Fixes TestRTag" and "Fixed tests."
- **2026 tracker documents were written by the agents doing the work.** I took their attributions ("caught by the Stage-1 pin", "exposed the gap") at face value where a commit corroborates them. I did not re-derive them from logs.
- **Keyword-driven search.** A catch described without words like red, falsified, caught, exposed, regress, flake or fail would be missed. I did not read the ~6,500-line L5-TERMINATION.md, most of the LSP stage reports, or the Lean READMEs in full.
- **Classification boundaries** are judgement calls, and each is marked `UNSURE`:
  - GATE vs SELF for TestDoc's import list.
  - REAL vs harness for the depCache fix.
  - Examples counted as product for SoftRelation.e.
  - Crediting co-detections to one suite only.
- **Counting unit.** Counts are distinct causes, not sightings. Pin flips inside large programmes are recorded only where a document or commit names the suite, so EXPECTED-CHANGE is not exhaustive for the 2026 pipeline rewrite. Compile-only or API adaptations of tests in the same commit as the product change are not counted.
- **Property counts are textual.** They include conditionally registered properties and `include`d property classes, and can differ from the per-run totals quoted in trackers.
- **Unresolved references.**
  - `8a8455ce` (cited by TICKET-stdlib-findings.md for E14) does not resolve here; I used 4359d644.
  - The fix SHA for TestRowRefusals' 2.11 vacuity (fbd6826a) comes from the review's F-1 and memory notes, not a diff.
  - The "Legend flake (6th sighting)" of 2026-08-30 (LSP-ROADMAP.md:2987) does not say whether it was TestLegend or TestErmineLegends, so it was not used.
