# E4 — `core/examples/Present/`: layout, charts, writers, validation and the report combinators

Stage E4 of `tracker/LOOP-MODEL-PLAN.md`. Brief `tracker/loopmodel/briefs/brief-E4.md` on top of
`briefs/brief-E-common.md`. Repository at `40f80aa` (branch `scala3-migration`), the three
row-solver defaults adopted (`-Dermine.rowSound` ON, `dequeuePolicy=smallcanon`,
`solveBudget=20000`). Every `bin/ermine` below ran with
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM at a time, 2026-09-07, on a
machine shared with two other example-writing agents (which is why wall clocks vary and the
compiler's own `Importing module` times do not).

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.useInterface=false" \
      bin/ermine core/examples/Present/Helpers.e core/examples/Present/<M>.e

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/E4/`. Boot is 13–16 s of every wall figure and
is excluded from the per-module times.

**Outcome: GREEN**, after the post-review corrections of 2026-09-07 (§7). Twelve `.e` modules
under `core/examples/Present/` — `Helpers.e` (34 row-polymorphic presentation helpers),
`Signatures.e`, `ProjectionCost.e`, and **nine** reports over fact tables of 15–30 columns —
plus **seven** negatives under `shouldfail/` and a group `README.md`; 19 `.e` files.

Everything that should load, loads, per file and in one batch; all seven negatives are rejected
with the diagnostics recorded in their own headers, across **five** refutation classes; the L2
differential is **128,501 segments, 0 skipped / 0 hashdiff / 0 eqdiff** on the positives and
**59,602** likewise on the negatives, the model reproducing **both** refutations including their
text — one of which is a **draw-budget stop**, the corpus's first, replayed at the same draw
count (20,009). The census is in §G3 and is the interesting part: the group's costliest solve
draws **6,804**, every draw a `Resolution` step and none a split, and the module that does it has
no data, no relation and no presentation in it (§4.10). `sbt core/test` is **913/914** — one
pre-existing failure, and the file-count constant that tripped for E2 and E3 has since been made
derived and now passes. 107 bindings evaluate cleanly in the REPL across two passes, and nine
relations compile to SQL and **execute** against SQLite.

---

## 1. The file table (G5)

| module | subject | fields per fact row | helpers used | shapes exercised | check, per file | in batch |
|---|---|---|---|---|---|---|
| `Helpers.e` | 34 generic presentation helpers | — | — | 34 signatures; **12** carry a row partition (**15** partition constraints), **5** carry an existential, 14 a class constraint | 0.93–1.40 s | 1.39 s |
| `SalesDashboard.e` | a dashboard page: six charts, three KPI tiles, a soft grid | **21** | `chartOf`×5, `chartOfAll`, `pieOf`, `keyedGrid`, `softGrid`, `withFormats`, `legendFor`, `groupedAs`, `scaledBy`, `sizedTo`, `spread`, `panel`, `kpi`, `dashboard` | ONE `chartOf` signature instantiated five ways (`bar`/`line`/`stackedBar`/`scatter`/`step`); `coloredSeries` + `categoryTickLabels` stacked on one series; `unscaled` and `scaled` axes side by side; a soft-schema grid whose columns are the data's own quarters; `chartOfAll` for a two-series comparison on one pair of axes | 1.14 s | 0.86 s |
| `VarianceStyling.e` | budget vs actual, conditionally formatted | **18** | `styledBy`, `bandedBy`, `accounting`, `aliasedBy`, `scaledBy`, `withFormats`, `labelled`, `relabelled`, `legendFor`, `pinned`, `groupedAs`, `cappedAt` | `Layout.Format`'s `conditional`/`colored`/`alias`/`constant`; nested conditionals as a three-band rule; a legend built from a ROW plus a naming function (`relabelled`); `Layout.Font` stacks through `atom'`; `Layout.BorderOptions` through `borderSize'`; scale-in-the-relation vs format-in-the-legend | 0.94 s | 0.51 s |
| `FulcrumPanel.e` | one quarterly grid, built two ways | **30** | `fulcrumOf`, `groupedAs`, `withFormats` | `Fulcrum.Dynamic` (`pivotTabular'`) with **28 columns in the identifier part**; `pivotColumn`'s rank-2 third argument at two formats chosen per key; `Fulcrum.Legendary`'s `RUnion2` chain four deep; `MythicalFulcrum` and `(><)` | 0.91 s | 0.87 s |
| `ValidationReport.e` | data quality: parameters and facts | **17** | `validated`, `outOfRange`, `missingKey`, `unreconciled`, `withFormats` | `Layout.Validation` over a four-field parameter row with errors ACCUMULATED; `Validation`'s `[...]_Vd`, `within`, `>=>`; three relational checks whose failures are relations of the same row, so they compose by `difference` | 0.68 s | 0.38 s |
| `DrilldownExplorer.e` | a three-level org tree with a control panel | **17** | `nestedOf`, `drilldownOf`, `withFormats`, `scaledBy`, `panel` | a THREE-element `DrilldownList` over three disjoint id pairs; every selector widget the stdlib has; `Syntax.Selector`'s `<$>`/`<*>` composing four; `zipSelector`, `mapSelector`, `unitSelector`, `sequenceSelector`, `makeSelectors`, `on`+`live`, `widget`; `drilldownPieChart` and `drilldownBarChart` | 1.31 s | 1.37 s |
| `WriterOutputs.e` | params → report → document | **15** | `written`, `writtenProfiled`, `withFormats` | all four `harness` forms; `Layout.Writer`'s functor/ap/monad/`runW`; `withProfiling`; `dumpQuery` and `dumpQueryInOrder` against the SQLite and MS SQL emitters — **the only output this build can produce** | 0.39 s | 0.32 s |
| `SortShowcase.e` | one table, four orderings | **16** | `sortedBy`, `againstBy`, `hiddenBy`, `pinned`, `withFormats`, `labelled`, `legendFor`, `scaledBy` | the four different things called a sort side by side (`Relation.Sort`, `SortPriority`, `SortStrategy`, `Ord {..k}`); a hidden sort column; `Layout.Column`'s `formatSortedV`/`sortPriority`/`keys`; `topK`/`bottomK`/`limit`/`invert`/`recordOrd`; `fromNumericOp` | 0.51 s | 0.56 s |
| `AtomicAndRelation.e` | the two report models, and the bridge | **18** | `pieOf`, `withFormats`, `panel` | `Atomic`/`atom`/`atom'`/`wrapped`/`val`/`fmt` against `tabular`; `valueGrid`/`valueGridN`/`valueGridR`/`grid`/`hflowLabeled`; `formatDate`/`formatDateFn`/`formatDateRangeFn` (the writer callback); `scanRelation`/`scanRelationInOrder`/`scan`+`runScan`; `Layout.Report.Relation.cutoffDrilldownRel`; `tree`, `tabbed`, `sideTabbed`, `collapsible`, `summaryDetail`, `sectionRibbon`, `floatSides` | 1.56 s | 2.52 s |
| `StyleGridHeatmap.e` | a 5×5 risk heat map | **16** | `bandedBy`, `labelled`, `withFormats`, `pieOf`, `sizedTo`, `cappedAt`, `panel` | `styleBox` — the only combinator that lays out by POSITION — with its two overlapping partitions; `StyleGrid` and `mapStyleGrid`; `Layout.Color` in full (`rgb`/`rgba`/`rgbRead`/`standardColors`); `Layout.Magnitude` in all three units plus `Area`/`Volume`; `treemapChart` | 0.68 s | 0.51 s |
| `ProjectionCost.e` | what a parameterised report costs the solver | — (no data at all) | — | the ladder: N reads of one unannotated record parameter, N = 2…6, against the same reads under one written partition. **The group's costliest solves live here** — see §4.10 and G3 | 1.21 s | 1.08 s |
| `Signatures.e` | the entailment proofs | — | — | 4 equivalence proofs (both directions), 1 tautology-elimination proof, 1 full 14-constraint / 11-existential `xFull` for `unreconciled` proved equivalent-by-specialisation, 2 further specialisations | 0.18 s | 0.27 s |
| `shouldfail/` ×7 | seven negatives | 1–5 | the helper each misuses | **five** refutation classes — four type-level plus the draw budget — see G1(c) | 0.03–2.71 s each | — |

Per-file wall clock is 18–24 s per module, of which 15–18 s is the stdlib boot on a machine
running another agent's JVM and four of its `looptrace` processes throughout — the first draft's
figures, taken on a quieter machine, were 15–21 s and 0.14–1.36 s of check time, and the
reviewer reproduced the eleven-module batch at 5.93 s exactly. **Nothing is over 30 s, nothing
needed `.slow`, and the draw budget never fires on a positive module** (it fires on one
negative, by design). Sum of the eleven positive modules' own check time on the post-review
bytes: **9.3 s** per file, **9.3 s** in one batch.

---

## 2. The helper signatures, verbatim, with their published residuals (G5)

All 34 helpers carry explicit signatures. Below, each signature exactly as written in
`Helpers.e`, followed by the line `core/examples/Present/Helpers.ei` publishes under a
`-Dermine.useInterface=true` load. **No weakening, no extra constraint, no residual the author
did not write**: every published line is the written one with the constraint list permuted,
`Has` expanded, and names qualified.

### legends

```
legendFor : forall r. Row r -> Legend_Lg r
```
published: `forall (r: rho). Relation.Row.Row r -> Layout.Legend.Legend r`

```
withFormats : forall k m r a. (r <- (k, m))
           => Legend_Lg k -> Format_Fmt a -> Row m -> Legend_Lg r
```
published: `forall (k: rho) a (m: rho) (r: rho). r <- (k, m) => Layout.Legend.Legend k -> Layout.Format.Format a -> Relation.Row.Row m -> Layout.Legend.Legend r`

```
labelled : forall r s t a pr. (t <- (r, s), AsPresentation pr)
        => pr r a -> String -> Legend_Lg s -> Legend_Lg t
```
published: `forall (pr: rho -> * -> *) (r: rho) a (s: rho) (t: rho). (AsPresentation pr, t <- (r, s)) => pr r a -> Builtin.String -> Layout.Legend.Legend s -> Layout.Legend.Legend t`

```
groupedAs  : forall r. String -> Legend_Lg r -> Legend_Lg r
relabelled : forall r. (String -> String) -> Row r -> Legend_Lg r
pinned     : forall r. String -> SortPriority -> Legend_Lg r -> Legend_Lg r
hiddenBy   : forall r a op. AsOp op => op r a -> SortPriority -> Legend_Lg r
```
published unchanged; `hiddenBy` as `forall (op: rho -> * -> *) (r: rho) a. AsOp op => op r a -> Layout.SortPriority.SortPriority -> Layout.Legend.Legend r`.

### presentations

```
styledBy : forall v n op. (AsOp op, PrimitiveNum n)
        => n -> Color -> Color -> Format_Fmt n -> op v n -> Presentation_Pres v n

bandedBy : forall v n op. (AsOp op, PrimitiveNum n)
        => n -> n -> Color -> Color -> Color -> Format_Fmt n
        -> op v n -> Presentation_Pres v n

accounting : forall n. PrimitiveNum n => Int -> Format_Fmt n

aliasedBy : forall v op. AsOp op
         => List (String, String) -> op v String -> Presentation_Pres v String
```
published: the same four, with `PrimitiveNum`/`Primitive` qualified as `Builtin.` and the class
list permuted. Note `styledBy`/`bandedBy` publish `AsOp op` — the REAL class; the *inferred*
form of the same body publishes an existentially quantified class variable instead (§4.3).

### sorting

```
sortedBy : forall r s t a b p1 p2. (t <- (r, s), AsPresentation p1, AsPresentation p2)
        => SortDirection_SS -> p1 r a -> SortDirection_SS -> p2 s b
        -> SortStrategy_SS t

againstBy : forall r a pr. AsPresentation pr => pr r a -> SortStrategy_SS r
```
published: `(AsPresentation p2, AsPresentation p1, t <- (r, s)) => …`; `againstBy` unchanged.

### magnitudes

```
sizedTo  : forall f z. MagnitudeList -> MagnitudeList -> Report f z -> Report f z
cappedAt : forall f z. List Area -> Report f z -> Report f z
spread   : forall f z. List (Double, Report f z) -> Report f z
scaledBy : forall v n op. (AsOp op, PrimitiveNum n) => n -> op v n -> Op_Op v n
```
published with `MagnitudeList` expanded to `Builtin.List Native.Magnitude.ErasedMagnitude` and
`Area` to `Native.Magnitude.Area` — the type synonyms are transparent in the interface.

### charts

```
chartOf : forall s x y r sr xr yr sa xa ya rel f z.
          (exists o. AsPresentation s, AsOp x, AsOp y, r <- (sr, xr, yr, o),
                     Relational rel, Primitive xa, Primitive ya)
       => String -> Axis xa -> Axis ya
       -> (s sr sa -> x xr xa -> y yr ya -> rel (|..r|) -> ChartSeries xa ya)
       -> s sr sa -> x xr xa -> y yr ya -> rel (|..r|) -> Report f z
```
published: `(exists (o: rho). Builtin.Primitive xa, AsOp y, Builtin.Relational rel, r <- (sr, xr, yr, o), Builtin.Primitive ya, AsOp x, AsPresentation s) => …` — the existential survives intact, and `rel (|..r|)` prints as `rel r`.

```
chartOfAll : forall xa ya f z. (Primitive xa, Primitive ya)
          => String -> Axis xa -> Axis ya -> List (ChartSeries xa ya) -> Report f z

pieOf : forall labels value r l d z rel prl prv f.
        (exists o. r <- (labels, value, o), Relational rel,
                   AsPresentation prl, AsPresentation prv, PrimitiveNum d)
     => String -> prl labels l -> prv value d -> rel (|..r|) -> Report f z
```
published unchanged modulo permutation.

### grids and drilldowns

```
softGrid : forall k v a b prk prv.
           (exists o. o <- (k, v), AsPresentation prk, AsPresentation prv)
        => prk k a -> prv v b -> SoftRelation_SR a b k v

keyedGrid : forall r k v i a b f z rel. (r <- (k, v, i), Relational rel)
         => SoftRelation_SR a b k v -> Legend_Lg i -> rel (|..r|) -> Report f z

fulcrumOf : forall k v. Row k -> ({..k} -> PivotColumn_DF v) -> DynamicFulcrum_DF k v

drilldownOf : forall r r1 r2 id v label f z rel.
              (exists o. r <- (r1, r2, v), v <- (label, o), Relational rel)
           => Legend_Lg v -> Field label String -> Field r1 id -> Field r2 id
           -> rel (|..r|) -> Report f z

nestedOf : forall r r1 v label f z rel.
           (exists o. Has r r1, Has r v, v <- (label, o), Relational rel)
        => Legend_Lg v -> Field label String -> DrilldownList_DDL r1
        -> rel (|..r|) -> rel (|..r|) -> Report f z
```
published: `keyedGrid`'s **three-part partition** `r <- (k, v, i)` intact; `fulcrumOf`'s `{..k}`
as `Builtin.Record k`; and — the one interesting rewrite — `nestedOf`'s two `Has` constraints
EXPANDED into existential partitions:

```
nestedOf : … (exists (o: rho) (c: rho) (c1: rho).
               r <- (r1, c1), r <- (v, c), Builtin.Relational rel, v <- (label, o)) => …
```

`Has r s` is sugar for `exists c. r <- (s, c)`, and the interface writes the sugar out.

### validation

```
validated : forall r f z.
            FormValidator_Vd r -> ({..r} -> Report f z) -> Map_Map String String
         -> Report f z

outOfRange : forall v o r n. (r <- (v, o), PrimitiveNum n)
          => Field v n -> n -> n -> Relation r -> Relation r

missingKey : forall h o r a. (r <- (h, o), Primitive a)
          => Field h (Nullable a) -> Relation r -> Relation r

unreconciled : forall a b c o r n. (r <- (a, b, c, o), PrimitiveNum n)
            => Field a n -> Field b n -> Field c n -> n -> Relation r -> Relation r
```
published: `validated` with `FormValidator` inlined
(`(Map.Map String String -> Either.Either (List Validation.Err) (Record r)) -> …`), which is
what a type synonym does. The other three publish **a free row variable the quantifier does not
bind** — see §4.2, a finding.

### writers

```
written : forall f z p.
          (Scanner f -> Runner f -> Writer f z) -> (p -> Report f z)
       -> Function3 (SMEnv DB -> Scanner f) (Runner f) p z

writtenProfiled : (same)
```
published verbatim, fully qualified. This is the type of every report entry point in the
`ermine-writers` project (§4.1).

### layout

```
panel     : forall f z. String -> Report f z -> Report f z
kpi       : forall f z. String -> Report f z -> Report f z
dashboard : forall f z. List (List (Report f z)) -> Report f z
```
published unchanged.

**Counts**, machine-counted over the published `Helpers.ei` (the first draft got all four
wrong; these are re-counted):

| | first draft | actual |
|---|---|---|
| signatures | 34 | **34** |
| carrying a row partition | 11 | **12** |
| partition constraints in all | 14 | **15** |
| carrying an existential | 6 | **5** |
| carrying `AsOp` / `AsPresentation` / `Relational` | 16 | **14** |

The twelve partition-carrying signatures are `withFormats`, `labelled`, `sortedBy`, `chartOf`,
`pieOf`, `softGrid`, `keyedGrid`, `drilldownOf`, `nestedOf`, `outOfRange`, `missingKey` and
`unreconciled`. The count of *constraints* exceeds the count of signatures because
**`drilldownOf` publishes two** (`v <- (label, o)` and `r <- (r1, r2, v)`) and **`nestedOf`
publishes three** (`r <- (r1, c1)`, `r <- (v, c)`, `v <- (label, o)` — the first two are its two
`Has`, written out). The five existential-carrying signatures are `chartOf`, `pieOf`, `softGrid`,
`drilldownOf` and `nestedOf`; `keyedGrid`'s three-part partition is universally quantified, which
is why it is the most informative single constraint in the file.

For comparison `Ai/Common.e` publishes 8 partitions across 4 signatures and `Time/Helpers.e` 38
across 23.

---

## 3. The gates

### G1(a) — every module loads, per file

Command per row: `bin/ermine core/examples/Present/Helpers.e core/examples/Present/<M>.e`,
one JVM each, `-Dermine.useInterface=false`. Re-measured 2026-09-07 on the post-review bytes:

```
AtomicAndRelation.e      wall=21s  Helpers 1.06 s   AtomicAndRelation 1.56 s
DrilldownExplorer.e      wall=24s  Helpers 1.40 s   DrilldownExplorer  1.31 s
FulcrumPanel.e           wall=22s  Helpers 1.11 s   FulcrumPanel       0.91 s
ProjectionCost.e         wall=19s  Helpers 0.98 s   ProjectionCost     1.21 s
SalesDashboard.e         wall=19s  Helpers 1.02 s   SalesDashboard     1.14 s
Signatures.e             wall=20s  Helpers 1.18 s   Signatures         0.18 s
SortShowcase.e           wall=19s  Helpers 0.93 s   SortShowcase       0.51 s
StyleGridHeatmap.e       wall=18s  Helpers 0.96 s   StyleGridHeatmap   0.68 s
ValidationReport.e       wall=22s  Helpers 1.16 s   ValidationReport   0.68 s
VarianceStyling.e        wall=23s  Helpers 1.23 s   VarianceStyling    0.94 s
WriterOutputs.e          wall=21s  Helpers 1.03 s   WriterOutputs      0.57 s
```

All LOADED. Wall clock 18–24 s per module, 15–18 s of which is the stdlib boot on a machine
running another agent's JVM throughout. **Nothing over 30 s; no module needed `.slow`; the draw
budget never fired on a positive module** — the one module that trips it is a negative, by
design (G1(c), §4.10).

`ProjectionCost.e` is the interesting row: it contains no data and no relation, and it is the
third most expensive module in the group to check, because five of its six definitions are the
draw ladder.

### G1(b) — every module loads in one batch

```
$ ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.useInterface=false" \
    bin/ermine core/examples/Present/Helpers.e core/examples/Present/{AtomicAndRelation,\
    DrilldownExplorer,FulcrumPanel,ProjectionCost,SalesDashboard,Signatures,SortShowcase,\
    StyleGridHeatmap,ValidationReport,VarianceStyling,WriterOutputs}.e

Importing module 'Present.Helpers'           (1.39 seconds)
Importing module 'Present.AtomicAndRelation' (2.52 seconds)
Importing module 'Present.DrilldownExplorer' (1.37 seconds)
Importing module 'Present.FulcrumPanel'      (0.87 seconds)
Importing module 'Present.ProjectionCost'    (1.08 seconds)
Importing module 'Present.SalesDashboard'    (0.86 seconds)
Importing module 'Present.Signatures'        (0.27 seconds)
Importing module 'Present.SortShowcase'      (0.56 seconds)
Importing module 'Present.StyleGridHeatmap'  (0.51 seconds)
Importing module 'Present.ValidationReport'  (0.38 seconds)
Importing module 'Present.VarianceStyling'   (0.51 seconds)
Importing module 'Present.WriterOutputs'     (0.32 seconds)
                                     total   10.64 s, wall 29 s
```

`Helpers.e` must come first: every module imports it. (The first draft's batch read 5.93 s over
eleven modules; this run adds `ProjectionCost.e` and ran against a competing JVM, so the figures
are not comparable module for module — the reviewer independently measured the eleven-module
batch at 5.93 s, exactly reproducing the first draft.)

### G1(c) — the seven negatives, each REJECTED with the recorded diagnostic

Command: `bin/ermine core/examples/Present/Helpers.e core/examples/Present/shouldfail/<M>.e`.
Each header carries its message verbatim; all seven are recorded and reproduce (the reviewer
reproduced the first six to the character, at the recorded line and column).

| module | mistake | diagnostic | class |
|---|---|---|---|
| `fmt01_currency_on_string.e` | currency format on a `String` column | `No instance for (PrimitiveNum String)` | class constraint |
| `leg01_legend_column_missing.e` | legend names a column the relation has not got | `failed to unify type (\|regionName, amountUsd, missingColumn\|) with type (\|regionName, amountUsd\|)` | row unification |
| `leg02_column_twice.e` | one column on both sides of `withFormats`'s partition | `Fields appear twice in row: Present.Shouldfail.Leg02.amountUsd` | duplicate field |
| `box01_position_in_legend.e` | `styleBox`'s position column also in its legend | `Fields appear twice in row: Present.Shouldfail.Box01.xPos` | duplicate field |
| `box02_treemap_same_measure.e` | treemap coloured and sized by one column | `Fields appear twice in row: Present.Shouldfail.Box02.nodeImpact` | duplicate field |
| `chart01_series_not_in_relation.e` | chart series column dropped by a projection | `Row partitions are unsatisfiable at field 'Present.Shouldfail.Chart01.channelName': the whole contains it but no part does` | partition refutation |
| `proj01_seven_reads.e` | **seven reads of one unannotated record parameter** | `Row solver resource limit reached (this is NOT a type error): … drew 20009 fresh row variables at this signature, past the -Dermine.solveBudget=20000 limit, so it was stopped rather than left to run.` | **draw budget** |

**Five** refutation classes. Six of the seven are rejected in 0.03–0.06 s; `proj01` takes
**2.71 s**, which is the budget being spent rather than a slow refutation, and is reported at
`1:1` because the offending signature is the module's own inferred one.

`proj01` is, as far as this stage can tell, **the only module in `core/examples` rejected by the
draw budget rather than by a type error** — which makes it the only place the corpus records
what the adopted `solveBudget=20000` actually does when it fires: a bounded stop with an
explanation naming the limit and how to raise it. §4.10 measures the ladder that leads to it.

**One negative had to be rewritten** during the first draft: `box01` first failed for the wrong
reason, `term definition would shadow global definition (cells)` — `Native.Magnitude.cells`. A
negative that fails for an uninteresting reason is not a negative; renamed and re-checked.
(§4.9(1).)

### G1(d) — `sbt core/test`

**913 / 914, Failed 1, Errors 0** (`sbt -batch core/test`, **289 s** wall):

```
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
[info] Failed: Total 914, Failed 1, Errors 0, Passed 913
```

The single failure is the **pre-existing** `Constraints.disjunction sound`, which E2 and E3 both
recorded, is documented twice in `Constraints.scala`, is deterministic, and reads no example
file.

**The file-count constant no longer trips.** The brief's fact (2) — that
`TestSurfaceParsers.scala:81`'s `(files ?= 271)` fires for every new group — was true when E2 and
E3 ran and is **no longer true**: a post-review correction has replaced the literal with a derived
count ("The count is DERIVED, not a constant … `files == moduleFiles.size` is exactly 'every file
in the corpus was compared and agreed'"). With **356** `.e` files on disk (161 stdlib + 195
examples, of which 19 are E4's — 354 at the time the reviewer counted, before this stage's two
new modules) the property now reads

```
[info] + Surface parser 2.3a.headers agree with the fused pipeline across the stdlib: OK, proved property.
```

so E4 needs **no wiring line for `TestSurfaceParsers.scala`** and E2's and E3's requests for one
are discharged. Every other corpus-wide property also passes over the enlarged tree:
`Tolerant read.strict and tolerant agree, and the tolerant read is silent, over the corpus`,
`Statement extents` ×4, `REPL eval goldens.corpus matches goldens`, and — the one that matters
most here — `loop model trace.the Lean loop model reproduces the compiler's trace, segment for
segment`.

`core/test`'s wall clock at 289 s is *below* E2's 405 s and E3's 468 s for the same suite, so the
group's 17 files add nothing measurable to it (the spread is machine load).

### G2 — the L2 differential on the group

    ERMINE_JAVA_OPTS="-Xmx3000m -XX:ActiveProcessorCount=2 -Dermine.useInterface=false \
      -Dermine.loadInSeries=true -Dermine.rowTrace=<scratch>/Present.tsv" bin/ermine <12 files>
    tracker/lean/.lake/build/bin/looptrace --replay <scratch>/Present.tsv
    tracker/tools/looptrace-diff.py --segments --lean … --scala … --report …

**The eleven positive modules plus `Helpers.e`** (re-measured 2026-09-07 on the post-review
bytes; trace 70 MB, ermine rc=0):

```
#summary  segments=128501  replayed=128501  skipped=0  hashdiff=0  eqdiff=0  nonpart=2032  rejected=0  fuel=0
```

**The seven negatives (`Helpers.e` + `shouldfail/*.e`)**, trace 33 MB:

```
#summary  segments=59602  replayed=59602  skipped=0  hashdiff=0  eqdiff=0  nonpart=1131  rejected=2  fuel=0
```

```
segments: scala=128501 lean=128501 compared=128501     segments: scala=59602 lean=59602 compared=59602
AGREE   128501                                          AGREE   59602
SKIP    0                                               SKIP    0
hashdiff segments: 0                                    hashdiff segments: 0
eqdiff segments: 0                                      eqdiff segments: 0
```

**0 skipped / 0 hashdiff / 0 eqdiff on both runs.**

The first draft reported 126,260 positive segments and the reviewer independently measured
126,756 on the same bytes — a difference the reviewer correctly attributed to the draft's
figures predating its own last edit (M-9). This run is 128,501, the extra ~1,700 being
`ProjectionCost.e` and its negative. All three runs are clean.

**Two rejected segments now, and the second is new and worth the space.** The model reproduces
both refutations *including their text*:

```
#REJECTED  59353  Row partitions are unsatisfiable at field
                  'Present.Shouldfail.Chart01.channelName': the whole contains it but no part does
#REJECTED  59601  Row solver budget exhausted at inferImplicitBindingTypes: the loop drew 20009
                  fresh row variables, budget 20000 (-Dermine.solveBudget); the row constraints
                  are too large or the solver is not converging
```

The second is `shouldfail/proj01_seven_reads.e`. **The Lean loop model implements the adopted
draw budget and stops at the same draw count as the compiler — 20,009 — on the same segment.**
As far as this stage can tell, that is the first time the corpus has contained a budget stop for
the differential to check, and it checks: the model agrees with the compiler not only about
which solves succeed but about *when the budget fires*. It is also the slowest segment either
side has to replay: the model spends about two minutes on it, against 2.7 s in the compiler.

The other five negatives never reach `Subst.solve`: `fmt01` fails in class resolution
(`No instance for (PrimitiveNum String)`), `leg01` in unification, and
`leg02`/`box01`/`box02` in row *construction* (`Fields appear twice in row`). That is worth
knowing about the corpus: **only two of seven presentation-layer mistakes reach the row solver**,
and one of those two is a resource stop rather than a refutation. The Algebra and Wide groups,
whose negatives are all about joins, are the opposite way round.

### G3 — the census over the group

`--depth`, `--cycle` and `--mints` over the same replay (all three are **modifiers of
`--replay`**, not standalone modes), filtered to the **55,259** segments whose location is
inside `core/examples/Present/`; the trace also carries the 73,242-segment stdlib boot, which is
identical on both sides.

| measure | **`Present/` (post-review)** | first draft | reviewer, pre-correction bytes | `Time/` (E3) | round 7/8 corpus |
|---|---|---|---|---|---|
| solves attributable to the group | **55,259** | 53,898 | 54,287 | 43,258 | — |
| verdicts | 55,259 SOLVED, 0 REJECTED | 53,898 / 0 | 54,287 / 0 | 43,256 / 2 | — |
| **draws per solve, max** | **6,804** | 225 ✗ | 218 | 13 | — |
| draws per solve, mean | 0.166 | 0.015 | 0.0149 | 0.03 | — |
| solves that draw at all | 299 (**0.54 %**) | 266 (0.49 %) | 271 (0.50 %) | 1.1 % | — |
| dequeues (`steps`), max / total | **686** / 14,825 | 79 / 13,608 ✗ | 73 / 13,682 | 60 / 16,360 | — |
| chain depth, max | **3** | 2 | 2 | 2 | ≤ 4 |
| **per-key mints, max (`--mints`)** | **1** | *(mislabelled as 12)* ✗ | 1 | 1 | ≤ 11 |
| `--cycle`'s `maxmint` — the minted **vocabulary** size | **60** | 12 ✗ | 11 | — | — |
| re-minted keys (`--mints remint`) | 0 | — | 0 | — | — |
| carrier re-mints (`cremint`) / carrier max (`cmax`) | 1 / 3 | — | 1 / 3 | — | — |
| initial mints (`mint0`), max | 4 | 4 ✔ | 4 | — | — |
| `concrete` share of dequeues | **21.1 %** (3,131/14,825) | 22.6 % | 22.6 % | 19.0 % | ~25 % |
| `concrete` share of solves | 5.33 % | 5.38 % | — | 6.2 % | — |
| vocabulary-fixed solves (`grew=false`) | **99.80 %** | 99.81 % | 99.81 % | 99.49 % | 97.4 % |
| generative rules fired (`grew=true`) | **0.20 %** (113) | 0.19 % (101) | 0.19 % (105) | 0.51 % | — |
| splits, max / total | 3 / 132 | 3 / 127 | 3 / 131 | 4 / 349 | — |
| **resolution steps, max / total** | **6,804 / 8,766** | 225 / 447 | 218 / 441 | 7 / 471 | — |
| input row variables / partitions / labels, max | 16 / 13 / 30 | 16 / 13 / 30 ✔ | 16 / 13 / 30 | 42 / 24 / 31 | — |
| `states`, max | 687 | 80 ✗ | 74 | 60 | — |
| distinct keys (`maxdkey`), max | 62 | 21 | — | — | — |

Derivation rules over the whole trace (`rowtrace-summary.py`): `Substitution` 1,339,
`CommonSubexpression` 682, **`Resolution` 634**, `SplitConcrete` 229, `Cancellation` 86,
`SplitKeyed` 20; 2,204 splice firings of which 1,243 changed the output; 350 dropped, 873
non-conservative. (`Resolution` 634 against the first draft's 120 is the ladder module.)

**Two corrections, both from the review.** "Per-key mints, max 12 — the first time the round-7/8
bound of 11 is exceeded" was **wrong twice** and is deleted: `--cycle`'s `maxmint` is the size of
the *minted-variable vocabulary* at a step (`Cycle.lean:407`, `max rep.maxMint mo.length` with
`mo = mintOrder s`), not a per-key count, and the per-key census is `--mints`, whose `max` over
this group is **1**. Its `--cycle` cousin is now reported under its own name (and is 60 here,
because `proj6` mints a 60-variable vocabulary). "Decision nodes (states)" is renamed `steps`.

**Budget, honestly.** The largest solve a *report* in this group performs is
`ValidationReport.e(214:14)` at **222 draws — 1.1 % of the adopted 20,000**. The largest solve
in the group is `ProjectionCost.e`'s `proj6` at **6,804 — 34 %**, and its seven-read sibling in
`shouldfail/` **exhausts** the budget at 20,009. All three are the same shape; the difference
between them is one field and one line of signature (§4.10). Reporting a "headroom" figure for
this group, as the first draft did, is meaningless: the group contains both the cheap end and
the cliff.

**The shape: a RESOLUTION cascade, and now it is measured end to end.**

Every previous corpus's costliest solves are *splitting* solves — a wide `combine` or a window
whose draws come from `SplitConcrete`. This group's are not:

```
 drawn=6804 nres=6804 nsplit=0 steps=686 nvars=7 nparts=6 nlbl=6 depth=3  ProjectionCost.e(1:1)   proj6
 drawn=1232 nres=1232 nsplit=0 steps=214 nvars=6 nparts=5 nlbl=5 depth=2  ProjectionCost.e(1:1)   proj5
 drawn=222  nres=222  nsplit=0 steps=74  nvars=6 nparts=5 nlbl=4 depth=2  ValidationReport.e(214:14)
 drawn=212  nres=212  nsplit=0 steps=72  nvars=5 nparts=4 nlbl=4 depth=2  ProjectionCost.e(1:1)   proj4
 drawn=39   nres=39   nsplit=0 steps=25  nvars=6 nparts=5 nlbl=3 depth=1  WriterOutputs.e(1:1)
 drawn=30   nres=30   nsplit=0 steps=19  nvars=4 nparts=3 nlbl=3 depth=1  ProjectionCost.e(1:1)   proj3
 drawn=30   nres=30   nsplit=0 steps=19  nvars=4 nparts=3 nlbl=3 depth=1  VarianceStyling.e(321:23)
 drawn=12   nres=7    nsplit=3 steps=48  nvars=6 nparts=5 nlbl=18 depth=2 SortShowcase.e(163:3)
```

**Seven of the eight costliest solves in the group are pure resolution with zero splits**, and
six of the eight are a record projected N times — the ladder module, the parameterised report
(`WriterOutputs.e(1:1)` is `asDocument`'s three-read parameter row), and
`VarianceStyling.e(321:23)`, which is the `scanRelation` continuation added by these very
corrections to compute the tiles. Only the eighth, `SortShowcase.e(163:3)` — two `combine`s onto
an 18-column row — is the shape the relational groups are full of, and it draws 12.

The widest *input* systems remain the plain predicate call sites rather than the presentational
ones:

```
 nvars=16 nparts=13 drawn=4   DrilldownExplorer.e(330:43)   atLeast: filter over a 17-column row
 nvars=16 nparts=13 drawn=4   WriterOutputs.e(185:48)       aboveValue: the same shape
 nvars=15 nparts=8  drawn=1   Helpers.e(353:1)              unreconciled's body
```

**What this says about presentation combinators as a corpus.** They are *narrow and deep* where
the relational corpora are *wide and flat*: 16 input variables at most against `Time/`'s 42, but
a 6,804-draw resolution cascade against `Time/`'s 13-draw maximum, and a chain depth of 3 that
`Time/` and `Ai/` do not reach for this reason. Legends, sort strategies and chart series compose
by `(++)`-style partitions that are individually tiny; what makes a presentation module expensive
is a *record* projected many times under one row variable — which is what `Layout.Validation`,
every parameterised report, and every `scanRelation` continuation does. That shape did not exist
in the corpus before this group.

### G4(a) — every report EVALUATED in the REPL

There is no `render` (§4.1). Nine modules, one JVM each (field names repeat across modules, so
they cannot share a session), driven non-interactively as `tracker/tools/repl-smoke.sh` does:

    bin/ermine core/examples/Present/Helpers.e core/examples/Present/<M>.e < <M>.in

**74 bindings evaluated across 9 modules in the first pass, plus 33 re-evaluated across 7
modules after the post-review corrections; zero errors** — except one embedded panic in a value
that forces `Native.Record.header#` (§4.6), which is a pre-existing compiler bug this group is
the first to reach.

Trimmed renderings, one per module:

```
############ SalesDashboard
>> res0..res5 : forall (f: * -> *) z. Report f z = (Report <function>)
     salesDashboard, revenueByRegion, brandedRevenue, categoryPie, quarterGrid, attainmentTable
>> res6 : Relation (|regionName, quarterName, revenueK|)
>> res7 : Relation (|quarterName, revenueK, targetK, regionName, attainment|)
>> res8 : Relation (|categoryName, categoryRevenue|)
>> res9 : Relation (|categoryName, unitsSold, marginPct|)

############ VarianceStyling
>> res0..res2 : Report                      -- varianceReport, styledGrid, escalatedGrid
>> res3 : Relation (|varianceK, yoyPct, accountGroup, lineId, periodName, centreName,
     variancePct, budgetM, actualK, accountName, ownerName, forecastGap, budgetK,
     approvalStatus, costCentre|)           -- 15 columns after the scale and the except
>> res5 : Presentation (|varianceK|) Double =
     Presentation(Conditional(Gte(...),ColorFormat(...),ColorFormat(...)), ...)
>> res7 : Presentation (|approvalStatus|) String =
     Presentation(Alias(List((Approved,Approved),(Pending,Awaiting sign-off),
                             (Escalated,**Escalated to the CFO**))), ...)

############ FulcrumPanel
>> res0..res3 : Report                      -- fulcrumPanel, quarterlyDynamic,
                                               quarterlyLegendary, quarterlyWide
>> res4 : Relation (|periodLabel, serviceGrade, terrainType, turbineName, turbineClass,
     energyMwh|)                            -- longForm
>> res5 : Relation (|… 30 columns …|)       -- turbines
>> res6 : MythicalFulcrum (|periodLabel|) (|energyMwh, availPct|) = (MF (LF (Fulcrum
     <error: Panic: unexpected runtime value in Record.header# - MapView(<not computed>)>
     ["energyMwh","energyMwh","energyMwh","energyMwh","availPct","availPct"] …
     (Legend [("Q1",Unsorted),("Q2",Unsorted),("Q3",Unsorted),("Q4",Unsorted),
              ("Q1 av",Unsorted),("Q2 av",Unsorted)] …)))
                                            -- §4.6: the type is right, the printer panics

############ ValidationReport
>> res0..res2 : Report                      -- qualityReport, goodParameters, badParameters
>> res3..res6 : Relation (|… 17 columns …|) -- badRates, orphanEntries, outOfBalance,
                                               cleanEntries; SAME row as the fact table,
                                               which is what makes them composable
       … supplierId -> StringT(0,true) …       -- (true) = nullable, the checked column
>> res7 : Relation (|checkName, failures|)

############ DrilldownExplorer
>> res0..res2 : Report                      -- explorer, teamTree, divisionTree
>> res3, res4 : Relation (|orgParent, … 16 more …|)   -- orgRoots, scaledNodes
>> res5..res7 : Report                      -- divisionPie, divisionBars, counter
>> res8 : forall (f: * -> *) z.
     (Report f z -> Selector f z (List String) -> Report f z) -> Report f z   -- levelRow

############ WriterOutputs
>> res0 : Report                            -- writerOutputs
>> res1 : Relation (|bookValue, segmentName|)
>> res2 : Relation (|… 15 columns …|)       -- active
>> res3 : Relation (|annualValue, accountName|)
>> res4 : forall (f: * -> *) z (a: rho).
     (exists (b: rho). a <- ((|pMinValue, pRegion, pTitle|), b)) =>
     (Scanner f -> Runner f -> Writer f z) ->
       Function3 (SMEnv DB -> Scanner f) (Runner f) (Record a) z      -- asDocument
>> res5 : the same                                                    -- asProfiledDocument

############ SortShowcase
>> res0..res5 : Report      -- sortingReport, byPriority, byStrategy, byHidden,
                               byColumnApi, positionGrid
>> res6..res9 : Relation (|teamName, positionName, assistCount, gamesPlayed, salaryUsd,
     playerName, minutesPlayed, reboundCount, contractYear, countryCode, playerId,
     efficiency, turnoverCount, salaryM, divisionName, ageYears, pointsPerGame,
     pointsScored|)         -- topScorers, cheapestFive, secondPage, enriched: 18 columns,
                               all four the SAME row, because topK/bottomK/limit are
                               row-preserving

############ AtomicAndRelation
>> res0..res2 : Report                      -- factsheet, dataSummary, twoScans
>> res3 : Relation (|sliceName, sliceId, sliceParent, sliceWeight|)   -- withOther
>> res4 : Relation (|… 18 columns …|)       -- sensors
>> res5 : Relation (|measurandName, measurandCost|)
>> res6, res7 : Report                      -- bucketedPie, sensorsTable

############ StyleGridHeatmap
>> res0, res1 : Report                      -- heatReport, heatMap
>> res2 : Relation (|riskId, … 15 more …|)
>> res3 : Relation (|nodeImpact, parentKey, nodeKey, nodeIntensity, nodeName|)
>> res4, res5 : Report                      -- impactMap, riskTable
>> res6 : Relation (|impactUsd, categoryName|)
>> res7 : List (Maybe String, List (Maybe String, String)) = [(Just "RISK-ROW SEVERE", …
                                            -- mapStyleGrid: cells shouted, classes kept
```

### G4(b) — the `.ei` for every module, and the round trip

`-Dermine.useInterface=true` over the whole group writes twelve interfaces, **298 published
signatures** in all:

```
Helpers.ei 34   AtomicAndRelation.ei 33   DrilldownExplorer.ei 31   StyleGridHeatmap.ei 29
WriterOutputs.ei 29   SortShowcase.ei 25   VarianceStyling.ei 25   SalesDashboard.ei 22
Signatures.ei 22   ValidationReport.ei 21   FulcrumPanel.ei 17   ProjectionCost.ei 10
```

(The first draft reported 18 for `SalesDashboard` and 21 for `VarianceStyling`; the reviewer
counted 19 and 24 on the same bytes and was right — the draft's figures were taken before its
last edit. Both modules have grown again since, hence 22 and 25 here.)

§2 lists what `Helpers.ei` publishes for every helper, machine-counted. A **second**
`useInterface=true` load, which reads those interfaces back instead of re-inferring, checks every
module again:

```
Importing module 'Present.Helpers' (1.01 seconds) … 'Present.WriterOutputs' (0.39 seconds)
```

so the interfaces round-trip, including the ones that print a free row variable (§4.2). All
`.ei` files were deleted afterwards, as the gate requires.

`ProjectionCost.ei` is worth reading on its own account — it is §4.10's mechanism in one screen.

### G4(c) — what CAN be rendered: relations compiled to SQL and executed

`Scanners.dumpQuery` needs a `Scanner` but not a connection. `Present/WriterOutputs.e` defines

```
lite = sqlite_Scanners cachedSMEnv
mss  = sqlServer_Scanners cachedSMEnv
sqlOfSummary = unsafePerformIO (dumpQuery_Scanners lite (summaryOf active))
```

and the REPL prints real SQL. Trimmed — the twelve-row literal relation is inlined as a UNION
of `select` constants, which is elided here as `…`:

```
>> sqlOfActive        (SQLite dialect)
"select (t.accountCode) accountCode, … , ('Active') subStatus, … from (select * from
 (select ('ACC-2001') accountCode, ('Northwind Traders') accountName, (220800.0) annualValue, …)
 UNION select * from (…) …) t where ((t.subStatus) = ('Active'))"

>> sqlOfEmea
… where ((t.subStatus) = ('Active')) and ((t.regionName) = ('EMEA'))

>> sqlOfSummary       -- aggregateByGroup
"select (SUM(t.annualValue)) bookValue, (t.segmentName) segmentName from (…) t
 where ((t.subStatus) = ('Active')) group by t.segmentName"

>> sqlOfOrdered       -- dumpQueryInOrder
"select distinct (t.accountName) accountName, (t.annualValue) annualValue from (…) t
 where ((t.subStatus) = ('Active')) order by t.accountName asc, t.annualValue asc"

>> sqlOfActiveMss     -- the MS SQL emitter, for comparison
"select ([t].[accountCode]) [accountCode], … from (select [accountCode],… from
 (values ('ACC-2001', 'Northwind Traders', 220800.0, …), …) as lit([accountCode],…)) [t]
 where (([t].[subStatus]) = ('Active'))"
```

Two dialects, a `where`, a `group by`, an `order by` and a `distinct`, all from the relations a
report draws. **This is the only rendering this repository can perform.**

**Executed.** `tracker/tools/sql-render.sh` (E1's tool, driven with `ERMINE_RENDER_MODULES` and a
scratch probe module — no shared file edited) compiles nine relations from three of the modules
and runs them against SQLite:

```
q_active: (9 rows)   q_emea: (5 rows)       q_summary: (3 rows)
q_byRegion: (9 rows) q_byCategory: (3 rows)
q_badRates: (3 rows) q_orphans: (3 rows)    q_unbalanced: (1 rows)   q_clean: (9 rows)
```

Four of the nine, whole:

```
== q_summary            (WriterOutputs.summaryOf active -- aggregateByGroup)
bookValue | segmentName
----------+------------
1158300.0 | Enterprise
 199200.0 | Mid-market
  17400.0 | SMB

== q_byRegion           (SalesDashboard.byRegionQuarter -- group, then scaledBy 1000)
quarterName | regionName | revenueK
------------+------------+---------
Q1 | AMER | 49.608599999999996        -- 35 511.0 + 14 097.6, in thousands
Q2 | AMER | 92.104
Q3 | AMER | 60.8188
Q1 | APAC | 87.4428     …9 rows

== q_badRates           (ValidationReport.outOfRange fxRate 0.5 5.0)
… | currencyCode | … | fxRate  | journalRef      | …
… | JPY          | … | 0.013   | JE-20110831-070 | …
… | JPY          | … | 0.0     | JE-20110228-011 | …
… | AUD          | … | 42.0    | JE-20110531-046 | …
(3 rows -- exactly the three impossible rates planted in the fact table)

== q_unbalanced         (ValidationReport.unreconciled creditAmt netAmt debitAmt 0.5)
… creditAmt 1200.0 | debitAmt 67400.0 | netAmt 67400.0 | JE-20110531-046 …
(1 row -- exactly the one line whose components do not add up)
```

So the relational half of these reports is not merely type-checked: it is **compiled to SQL,
executed, and returns the rows the module's own comments say it should**, including the three
generic validation helpers. The presentational half — legends, formats, charts, layout — is
where the writer would take over, and that is what cannot run here.

### G5 — this report, the plan row, the wiring lines, and what could not be written

This file; §5 for the wiring lines, §6 for what could not be written; a status row appended to
`tracker/LOOP-MODEL-PLAN.md` after the E3 row.

---

## 4. Findings

### 4.1 The writers exist, in a sibling project, and they all have one shape

The brief asks what `Layout.Writer` outputs can and cannot be produced without a database. The
precise answer:

**`Layout/Writer.e` declares the type `foreign` and gives it no constructor.** Everything it
exports is an interpreter interface — `pureW`, `bindW`, `mapW`, `apW`, `runW`, plus `live` and
`orEvent` for selector events. `core/src/main/scala/.../writers/Writer.scala` defines only the
abstract class. So `Writer f z` is uninhabited on this classpath, and neither `harness` nor
anything downstream of it can be run.

**Six concrete writers live in `/home/dmitry/research/ermine/ermine-writers`**, each with an
Ermine-facing module, and every writer constructor in all six has the type
`Scanner f -> Runner f -> Writer f z` — some modules export more than one:

| module | writer CONSTRUCTOR(s) | entry point(s) | produces |
|---|---|---|---|
| `Layout.Writer.HTML` | `htmlWriterRemote`, `htmlWriterLocal` | `html`, `htmlLocal` (+ primed) | `HJS` — HTML + JS; *remote* has charts and tables fetch their own data, *local* inlines it |
| `Layout.Writer.Json` | `jsonWriterFancy`, `jsonWriterDense` | `jsonFancy`, `jsonDense` | a JSON document |
| `Layout.Writer.JsonDebug` | `jsonWriterFancy`, `jsonWriterDense` | `jsonFancy`, `jsonDense` | JSON with layout debugging |
| `Layout.Writer.Csv` | `csvWriter` | `csv`, `csv'` | CSV |
| `Layout.Writer.JavaFX` | `javaFXWriter` | **none** | a `javafx.scene.Node` |
| `Layout.Writer.PDF` | `pdfWriter ro path` | **none** (`writePdf` instead) | PDF, through the HTML writer |

and **four of the six** — HTML, Json, JsonDebug and Csv, i.e. every one that has a `harness`
entry point at all — define it with the same four lines (`grep -l function3` over the six
modules returns exactly those four):

```
runHtml w f = function3 $ scanner runner params ->
                unsafePerformIO $ harness' scanner runner w (f params)
```

`JavaFX.e` is six lines and exports only the foreign constructor; `PDF.e` exports
`pdfWriter`/`writePdf` and leaves the harnessing to its caller. So the *type* is universal and
the *idiom* is the majority, which is the honest form of the claim.

`Helpers.written` is that, written once and generic in the writer; `Present/WriterOutputs.e`
type-checks it and documents the pipeline. **A report is a function from its parameters and the
writer is chosen at the boundary** — the production shape of `tracker/JSON-API-DESIGN.md`,
confirmed from the writers' own source rather than asserted.

The REPL shows the contract the row solver derives for such an entry point:

```
>> asDocument
res4 : forall (f: * -> *) z (a: rho).
    (exists (b: rho). a <- ((|pMinValue, pRegion, pTitle|), b)) =>
    (Scanner f -> Runner f -> Writer f z) ->
      Function3 (SMEnv DB -> Scanner f) (Runner f) (Record a) z
```

— the parameter record must carry *at least* the three fields the report reads. The report's
parameter contract is a row constraint, and it is inferred.

**And the obstacle is the WRITER, not the database.** An earlier draft of this report, and of
the group README, said "every constructor of both [`Scanner` and `Runner`] is a database
connection". That is false and it matters, because it makes the gap look bigger than it is:

```
Runners.e :  function "…backends.Runners" "SQLite" sqlite : String -> Runner DB
Scanners.e:  method   "SQLite"                     sqlite#: ScannersModule -> SMEnv f -> Scanner f
```

A `Runner` is built from a **JDBC URL string**, and `jdbc:sqlite::memory:` is a legal one; the
driver (`sqlite-jdbc`) is already on `target/ermine-classpath`, which is exactly how
`tracker/tools/sql-render.sh` executes this group's queries against an empty database today —
every relation here is a literal, so it compiles to a table-value constructor and needs no
schema. **A live in-memory `Scanner`/`Runner` pair is available now.** The only genuinely
missing piece is a concrete `Writer`, which is a classpath fact and not a language one: the CSV
and JSON writers have no browser or JavaFX dependency, and putting their jar *and* their
`modules/` resource root on the classpath would make
`harness' (sqlite cachedSMEnv) (Runners.sqlite "jdbc:sqlite::memory:") csvWriter someReport`
run. That is the single highest-value follow-up this group points at.

**What CAN be produced here today: SQL, and it runs.** `Scanners.dumpQuery` needs a `Scanner` but not a
connection — only its emitter — so it works with `sqlite cachedSMEnv`. Nine relations across
three modules dump to real SQL and **execute against SQLite** through E1's
`tracker/tools/sql-render.sh`, returning exactly the rows the modules' comments predict,
including all three generic validation checks; see G4(c). One correction to
`tracker/loopmodel/E1-EXAMPLES.md` §7.4: **`aggregateByGroup` dumps fine** (it emits
`select SUM(...) … group by …` and returns three rows here); the "Don't know how to dump a mem"
limit is `groupBy`'s `Mem`, not aggregation as such.

### 4.2 The published interface names a row variable it does not bind

`missingKey`, `outOfRange` and `unreconciled` are written with `forall h o r a. r <- (h, o) => …`
where `o` is the carried remainder. The `.ei` publishes

```
missingKey : forall (h: rho) a (r: rho). (Builtin.Primitive a, r <- (h, o)) => …
outOfRange : forall (v: rho) n (r: rho). (Builtin.PrimitiveNum n, r <- (v, o)) => …
unreconciled : forall (a: rho) n (b: rho) (c: rho) (r: rho). (…, r <- (a, b, c, o)) => …
```

— `o` appears in the constraint and **not** in the `forall`. Every other row variable that
occurs only in constraints (`chartOf`'s `o`, `pieOf`'s `o`, `nestedOf`'s three) is correctly
published under `exists`. The difference is that those are genuinely existential in the source,
while `o` here was written as a universally quantified variable that happens not to appear in
the term type; the printer drops it from the quantifier list and does not move it to the
existential list.

**Effect measured:** the interface round-trips — a second `-Dermine.useInterface=true` load
reads these `.ei` files back and every module still checks (G4(b)) — so this is a *printing*
defect and not a soundness one. It matters because the `.ei` is what a reader is shown when
they ask what a helper's type is, and a free variable in a printed type is not a type.

### 4.3 An inferred signature that cannot be written down: the existential class

Removing the signature from `styledBy`, `hiddenBy` or `outOfRange` and re-inferring gives, for
each, a constraint of the form

```
(exists (AsOp: b). AsOp op, Relation.Op.AsOp op)
```

— **two** `AsOp` constraints on the same variable, one of them headed by an existentially
quantified variable *named after the class*, of an unnamed kind. There is no source syntax for
a class variable, so these inferred signatures cannot be written back into a module: E-series
convention asks for an `xFull` that carries the inferred set verbatim, and for **these three**
helpers `xFull` is unwritable. `Present/Signatures.e` says so and gives `xSimple` (or the
largest writable generalisation) instead.

**It is not a property of `AsOp`-polymorphism as such**, which an earlier draft of this report
and of `Signatures.e` claimed for five helpers. Measured with each body alone in a module — the
precaution `Signatures.e`'s own header demands — `scaledBy` infers
`(c <- (c), Relation.Op.AsOp b, PrimitiveNum a)` and `unreconciled` infers three plain
`Relation.Op.AsOp` constraints; both are the real class, and `unreconciled`'s whole inferred set
is now written out and proved in `Signatures.e` (below). The count is **three of five tested**.

Whether the existential class is a printer artefact (the classy-dictionary encoding leaking a
skolem) or a real unresolved class variable in the residual is **open**. It is visible only in
inferred signatures: every hand-annotated `AsOp` helper publishes the plain class.

### 4.4 The size of the gap between an inferred type and a written one

`unreconciled`'s inferred constraint set, in full:

```
(exists b1 d1 e1 f1 c1 d2 j e2 f2 c2 c3.
   i <- (j, e, d2, d1, c1),  g <- (e1, d1),  c3 <- (f2, e2, d2),
   AsOp a,                   e <- (f2, e2),  AsOp d,
   RelationalComb h,         PrimitiveNum c, b <- (e2, d2),
   b1 <- (e, d2, d1, c1),    c2 <- (f1, e1, d1),
   b1 <- (c1, f1, e1, d1),   AsOp f,         c3 <- (f1, e1))
```

**Eleven existentials, fourteen constraints, nine of them partitions** — for a helper whose
meaning is "these three columns are in this relation". Written by hand it is **one partition**.
The inferred set is not wrong: `abs (total - (p1 + p2))` really does need one partition per
intermediate `Op`. It is the difference between the type of a *body* and the type of an *idea*,
and it is the whole argument for a hand-written helper library. A caller who had to discharge
fourteen constraints per call site would not use the helper twice.

`chartOf` shows the same lesson from the other side: its inferred type knows **nothing** about
rows —

```
forall {a b} (xa: a) (ya: b) c d e f (f1: * -> *) z. (Primitive xa, Primitive ya)
  => String -> Axis xa -> Axis ya -> (c -> d -> e -> f -> ChartSeries xa ya)
  -> c -> d -> e -> f -> Report f1 z
```

— four unrelated type variables where the series, category, value and relation should be. It
would let a caller pass a series selector for one relation and a value selector for another.
The written signature is *strictly stronger* than the inferred one, and `Signatures.e` checks
the body at it, which is the proof the extra information is true.

### 4.10 THE FINDING: a projected record parameter costs ~6x per read, and seven reads do not compile

This is the group's most consequential measurement and it was not in the first draft; it comes
out of asking whether §G3's 218-draw solve is realistic. It is, and it is the *cheap* case.

`Record.(!)` is a row PARTITION, not a lookup:

```
(!) : t <- (r, s) => {..t} -> Field r a -> a
```

So a lambda that reads N fields out of one **unannotated** record parameter hands the solver N
partitions that share a left-hand side and have N different right-hand sides, and it must close
them against one another. Measured on `core/examples/Present/ProjectionCost.e`, whose entire
content is that ladder and nothing else — no relation, no join, no presentation:

| reads | input partitions | draws | steps | splits |
|---|---|---|---|---|
| 2 | 2 | 3 | 5 | 0 |
| 3 | 3 | 30 | 19 | 0 |
| 4 | 4 | 212 | 72 | 0 |
| 5 | 5 | 1,232 | 214 | 0 |
| 6 | 6 | **6,804** | 686 | 0 |
| 7 | 7 | **budget exhausted** | — | — |

**Seven reads of one record do not compile.** `core/examples/Present/shouldfail/proj01_seven_reads.e`
is one lambda, seven `p ! field`, and it is rejected in 2.71 s with

```
Row solver resource limit reached (this is NOT a type error): the row constraint solver drew
20009 fresh row variables at this signature, past the -Dermine.solveBudget=20000 limit, so it
was stopped rather than left to run.  Raise the limit with -Dermine.solveBudget=<n>, simplify
the row constraints at this signature, or report it.
```

It is the only module in `core/examples` rejected by the draw budget rather than by a type
error, and the diagnostic is exactly what the adopted budget was adopted to produce: a bounded
stop with an explanation, not a hang. **The Lean loop model replays that segment and stops at
the same draw count** (G2), which is the first time the corpus has given the differential a
budget stop to check.

**What the residual looks like, which is the mechanism in one screen.**
`core/examples/Present/ProjectionCost.ei`, published by a `-Dermine.useInterface=true` load
(module qualifiers trimmed):

```
proj2 : forall a. (exists b. a <- ((|pAlpha, pBeta|), b)) => Record a -> String
proj3 : forall a. (exists b. a <- ((|pAlpha, pBeta, pGamma|), b)) => Record a -> String
proj4 : forall a. (exists b. a <- ((|pGamma, pAlpha, pBeta, pDelta|), b)) => Record a -> String
proj5 : forall a. (exists b c d e.
          a <- ((|pEpsilon, pBeta, pDelta, pAlpha, pGamma|), e),
          a <- ((|pGamma, pAlpha, pDelta, pBeta|), d),
          a <- ((|pAlpha, pEpsilon, pDelta, pGamma|), c),
          a <- ((|pAlpha, pDelta, pBeta, pEpsilon|), b))    => Record a -> String
proj6 : forall a. (exists b c.
          a <- ((|pEpsilon, pBeta, pDelta, pAlpha, pZeta, pGamma|), c),
          a <- ((|pEpsilon, pBeta, pDelta, pZeta, pGamma|), b)) => Record a -> String
proj5Pinned : forall r. r <- ((|pEpsilon, pBeta, pDelta, pAlpha, pGamma|), o) => Record r -> String
```

Two, three and four reads each publish **one** partition. Five publishes **four** — four
rotations and sub-multisets of the same five-field row against four different remainders — and
that is the closure the draws are spent on. (These four are **not** the permuted duplicates stage S3's `NormalPart.hashCode` change
removes — that change was already compiled in when this was measured, and the four differ in
their existential remainders `b`, `c`, `d`, `e`. They are four genuinely different partitions
over one row.)
`proj5Pinned` publishes exactly what was written — and, incidentally, is a third instance of the
free-variable printing defect of §4.2: `o` is bound nowhere.

**The remedy is one line, and it costs nothing.** `ProjectionCost.proj5Pinned` has the identical
body to `proj5` under a written signature —

```
proj5Pinned : forall r o. r <- ((| pAlpha, pBeta, pGamma, pDelta, pEpsilon |), o)
           => {..r} -> String
```

— and draws ****nothing at all** — it is one of the module's 434 zero-draw solves**. The partition is given rather than discovered, so there is nothing
to close.

**Why this matters to this group in particular.** params → report is the production shape
(`tracker/JSON-API-DESIGN.md`), it is what `Helpers.written` exists for, and it is what
`WriterOutputs.reportFor` and `ValidationReport.parameterised` both are. The REPL prints
`asDocument`'s inferred parameter contract as
`(exists b. a <- ((|pMinValue, pRegion, pTitle|), b))` — three reads, already on the ladder.
`ValidationReport.e(214:14)`, the group's costliest hand-written solve at **222** draws, reads
its parameter record five times and costs 222 rather than 1,232 **only because
`Layout.Validation`'s `FormValidator r` fixes `r` to a concrete four-field row before the reads
happen**. A reader who writes the same report over a bare record pays the ladder.

So the first draft's "**budget headroom 89x**" was the wrong sentence to end the census on. The
honest one: *the largest solve a **report** in this group performs uses 1.1 % of the budget
(222 of 20,000); the same group contains a five-line definition that uses **34 %** of it
(`proj6`, 6,804) and a seven-line one that **exhausts** it — and the difference between the last
two and the first is one line of signature.* The rule is the one `Helpers.e` preaches
everywhere else, applied one level out: **write the parameter row down.**

Worth a solver ticket as well as a README line: the closure is doing work that a single
left-hand-side index would avoid.

### 4.5 The Ai README's `RUnion` cliff does not reproduce — measured on `RUnion2`, chained

The `core/examples/Ai/README.md` warning ("a helper whose signature bundles `RUnion3` **and**
`RUnion2` … does not finish") is the reason `Ai/Common.e` is shaped as it is. E3 measured that
`if`-based `Op` helpers are now cheap. E4 measures the other constructor:

`Layout.Report.Fulcrum.Legendary.snoc_Brace` carries `(s <- (f,p), RUnion2 v3 v2 v1)` **per
link**, and `(<>)`/`(><)` carry another `RUnion2` each. `FulcrumPanel.e` chains four `snoc`s,
wraps the result in `fulcrumGroup`, pattern-matches it apart, feeds it to `Relation.Pivot.pivot`
(itself `r <- (k, v, i), s <- (i, p)`), and separately builds a second two-link chain and joins
the two with `(><)` — all against a 30-column fact table.

**The whole module checks in 0.96 s per file / 0.51 s in batch**, and its largest solve is
reported in G3. At the adopted defaults the cliff is not there.

### 4.6 `Native.Record.header#` has the `MapView` bug, and this group forces it

`tracker/loopmodel/E1-EXAMPLES.md` §7.2 diagnosed `Native.Record.scalaRecord#` panicking on the
lazy `MapView` that `record#` returns since Scala 2.13, and noted that `Native.Record.header#`
(`Lib.scala:1016`) "has the same `case Prim(r : Map[String,Runtime])` pattern and is presumably
in the same position, though nothing here forced it."

`Present/FulcrumPanel.e` forces it. Evaluating `bothHalves` (a `MythicalFulcrum`, built through
`Legendary.emptyLF` → `nilFulcrum (header k)`) prints the value with

```
<error: Panic: unexpected runtime value in Record.header# - MapView(<not computed>)>
```

embedded in it. Same root cause, same one-character fix (`.toMap`), second confirmed site. Not
applied here for the same reason E1 did not apply it: recompiling the compiler mid-stage would
invalidate every measurement in this report.

### 4.7 A REPL trap that makes an example unusable from a script

`Console.other` (`Console.scala:623`) decides whether a typed line is finished by asking, among
other things, whether the line **contains the substring** `"case"`, `"let"` or `"where"`:

```scala
val verbose = Set("case","let","where")
while ((needMoar || (balanced(input) == Unbalanced) || verbose.exists(input.contains(_))) && !blank) {
  val last = e.readLine("|> "); blank = last == ""; if (!blank) { input = input + "\n" + last }
}
```

The report in `SortShowcase.e` was called `sortShowcase`. "show**case**" contains "case", so a
piped `bin/ermine … < script` prompted `|>` for six minutes before the JVM was killed, sitting
in `Console.balanced`.

**It is worse than "floods `|>`": the loop cannot terminate.** `readLine`
(`Console.scala:146–151`) returns **`null`** on `EndOfFileException`, and in Scala `null == ""`
is `false`, so `blank` never becomes true. Each iteration appends `"\n" + null` — five
characters — and the guard then re-runs `balanced(input)` (a recursive walk of the whole string)
and three `String.contains` scans over an ever-longer string. Quadratic in time, unbounded in
memory, and no amount of waiting ends it. Measured here, minimal input, no module loaded:

```
printf 'staircase\n' | bin/ermine    exit=124 (killed at 40 s)   2,090 `|> ` prompts
printf 'palette\n'   | bin/ermine    exit=124 (killed at 40 s)   2,884 `|> ` prompts
printf 'staircas\n'  | bin/ermine    exit=0                          0 prompts
printf 'latest\n'    | bin/ermine    exit=0                          0 prompts
printf 'casing\n'    | bin/ermine    exit=0                          0 prompts
```

**It is triggered by a substring of an IDENTIFIER, not by a keyword.** Genuine offenders:
`showcase`, `staircase`, `complete`, `delete`, `palette`, `elsewhere`. An earlier draft of this
report and of the group README also listed `latest` and `casing`; **both are wrong** — `latest`
is l-a-t-e-s-t and `casing` is c-a-s-i-n-g, neither contains any of the three substrings, and
both exit 0 with zero prompts when piped (measured above). Two independent one-line fixes:
test the three words as *tokens*, or treat a `null` read as end of input.

### 4.8 The blame wording for a partition is backwards, again

`shouldfail/chart01_series_not_in_relation.e` — a chart series column dropped by a projection —
is correctly rejected at the right field with

```
Row partitions are unsatisfiable at field 'Present.Shouldfail.Chart01.channelName':
the whole contains it but no part does
```

but here a **part** (the series row) contains it and the **whole** (the projected relation) does
not; the sentence describes the opposite situation. This is
`tracker/loopmodel/E1-EXAMPLES.md` §7.5 reproduced independently, from a chart rather than a
window. Recorded, not fixed.

### 4.9 Five small language facts a reader of these examples will need

Each cost a compile here and is now documented in the module that hit it.

1. **A field may not shadow a stdlib global.** `field product`, `field grid`, `field tree`,
   `field cells` are all rejected with `term definition would shadow global definition`. The
   error is good; the surprise is how many ordinary column names are taken (`product` and
   `cells` are `List.product` and `Native.Magnitude.cells`).
2. **`map` is not in `Prelude`'s unqualified scope.** `Prelude` exports both `List` and
   `Syntax.List as List`, and the unqualified `map` comes from `Syntax.List`, which must be
   imported explicitly. `import Prelude; import Layout` alone gives `undefined term` for `map`.
3. **`Op` arithmetic is homogeneous.** `pointsScored / gamesPlayed` on two `Int` columns will
   not silently produce a `Double`; `Relation.Op.fromNumericOp` is the widening.
4. **`'` is `infixl 0`,** so `f ' g ' x` is `(f ' g) ' x`. A right-nested chain of legend
   combinators has to be built with `.` and applied once, not chained with `'`.
5. **`{..r}` is sugar that needs a row VARIABLE; for a concrete row write `Record (| … |)`.**
   `Ord {..(| positionName |)}` is a parse error (`expected '=', pattern atom, or whitespace`),
   which is what an earlier draft of this report generalised — wrongly — into "there is no
   type-level syntax for a record over a concrete row". There is: the spelling the interface
   printer itself uses works in source. `byPositionRank : Ord (Record (| positionName |))` and
   `byPointsRecordOrd : Ord (Record (| pointsScored |))` are both back in `SortShowcase.e` and
   both check. The real limitation is only the sugar.

---

## 5. Wiring — what is applied, and the two lines that are not

E4 edits nothing outside `core/examples/Present/`, `tracker/loopmodel/E4-EXAMPLES.md` and its
own row in `tracker/LOOP-MODEL-PLAN.md`. Re-checked against the tree on 2026-09-07 after the
post-review corrections:

| file | asked for | state |
|---|---|---|
| `tracker/tools/looptrace-corpus.sh` | `Present)` / `Present-shouldfail)` cases hoisting `Helpers.e`, and both names in the default `groups=` list | **applied** |
| `tracker/tools/corpus-run.sh` | the group in `files=`, the batch hoist, **and** the per-file hoist | **applied**, all three (lines 108–109, 133–135, 170–171) |
| `core/examples/README.md` | a directory-table row, an example command, `Present/shouldfail/` in the shouldfail paragraph | **applied** (lines 23, 31, 39) |
| `TestSurfaceParsers.scala` | nothing — the `(files ?= 271)` constant has been made derived | nothing to do |

**Two stale counts for the orchestrator, both caused by this stage growing after the review.**

1. `tracker/tools/corpus-run.sh:73` says `core/examples/Present/*.e (11), core/examples/Present/shouldfail/*.e (6)`.
   The group is now **12** and **7** — `ProjectionCost.e` and `shouldfail/proj01_seven_reads.e`
   were added by these corrections. The comment is documentation only; the globs are correct
   and pick both up.
2. `core/examples/README.md:23` says "nine reports over **presentation**". Nine reports is still
   right, but the group also carries `Helpers.e`, `Signatures.e` and now `ProjectionCost.e`, so
   "nine reports plus a helper library, its proofs and a solver-cost measurement" is the accurate
   phrasing if anyone is editing that line anyway.

**One correction to a comment the orchestrator copied from this report's first draft.** The
`Present)` case in `looptrace-corpus.sh` carries "every module under `Present/shouldfail` imports
`Present.Helpers`". Only two of the seven do (`leg02`, `chart01`); the rest are stdlib-only.
Hoisting the library is free, so the wiring is correct and only the comment is wrong. (The same
sentence appears for `Wide`, `Algebra` and `Time`.)

## 6. What could NOT be written, and why

Six things, in descending order of how much they matter to a reader.

### 6.1 The PRESENTATION half cannot be run from this repository

`written` is the right shape and it type-checks; there is simply no `Writer f z` value to give
it. Six writers exist in `ermine-writers` (§4.1) and none is on this classpath. What was
delivered instead is (a) the writer-generic entry point, checked; (b) the exact type of every
writer constructor and the idiom the four harnessed ones share, documented from their source;
and (c) the relational half compiled to SQL and **executed** (G4(c)). So a legend, a format, a
chart series and a layout can be checked but not drawn; a join, a filter, a group and an order
can be checked, drawn as SQL, and run.

**It is one jar, not a database.** `Runners.sqlite` takes a JDBC URL and
`jdbc:sqlite::memory:` works with the driver already on this classpath (§4.1), so the
`Scanner`/`Runner` half is available today. The missing half is a concrete `Writer` class on
the classpath plus its `modules/` resource root — for CSV or JSON, neither of which pulls in a
browser or JavaFX. A follow-up stage that does that would turn `written` from a type-check into
a rendering, and it is the highest-value follow-up this group points at.

### 6.2 A `StyleGrid` cannot be BUILT from a relation

`Layout.Report.StyleGrid`'s type is
`List (Maybe String, List (Maybe String, a))` — a fully materialised grid of optional CSS
classes. Nothing in the stdlib turns a relation into one: `toStyleGrid#` converts an Ermine
`StyleGrid` to the native one, and `mapStyleGrid` is its functor, but the *rows* must be a
literal list. To build one from data a report would have to `scanRelation` first and then fold
the rows into nested lists, which is possible but is a value-level program, not a relational
one, and the class strings are then computed in Ermine rather than by the writer. The example
therefore builds one by hand and says so. **The real conditional-styling mechanism in this
library is `Layout.Format.conditional`**, attached to a column, and that is what
`VarianceStyling.e` and `StyleGridHeatmap.e` use.

### 6.3 (WITHDRAWN) An `Ord` over a concrete key record CAN be given a signature

This entry said the opposite in the first draft and it was wrong. `{..r}` is sugar that needs a
row variable, but `Ord (Record (| positionName |))` — the interface printer's own spelling —
is accepted, and both signatures are back in `SortShowcase.e`. Kept as a withdrawn entry
because the parse error the sugar produces is genuinely misleading and a reader may repeat the
mistake. §4.9(5).

### 6.4 The inferred signature of three helpers cannot be written back

§4.3. `styledBy`, `hiddenBy` and `outOfRange` infer an existentially quantified CLASS, for which
there is no source syntax, so `xFull` is impossible for those three and `Signatures.e` gives
`xSimple` or the largest writable generalisation. **Not** five: `scaledBy` and `unreconciled`
infer only real classes, and `unreconciled`'s full inferred set — eleven existentials, fourteen
constraints — is now written out in `Signatures.e` and proved equivalent-by-specialisation to
the one-partition signature `Helpers.e` carries.

### 6.5 A per-key `PivotColumn` cannot choose its own COLUMN TYPE

`Layout.Report.Fulcrum.Dynamic.pivotColumn : Op v a -> String -> (forall f. Field f a ->
Presentation f a) -> PivotColumn v` fixes `a` — the value type — across every column of the
fulcrum, because `DynamicFulcrum`'s third field is `{..k} -> PivotColumn v` and `PivotColumn v`
existentially hides `a` *per column* but the `Op v a` handed in is chosen once. In practice a
per-key `if` can choose the FORMAT (as `FulcrumPanel.quarterColumn` does — currency for Q4,
rounding for the rest) but not the underlying type. A fulcrum with a `Double` column and a
`Date` column beside it is not expressible this way; `Legendary` is, which is one more reason
the two exist.

### 6.6 `Layout.Magnitude` has nothing to do with scaling a number

The brief asks for a `withMagnitudes` that does "`Layout.Magnitude` scaling of a generic measure
row". `Layout.Magnitude` re-exports `Native.Magnitude`, whose entire content is `cells`,
`pixels`, `dimensionless`, `Area` and `Volume` — **box sizes on a page**. There is no numeric
scaling in it. The helper was therefore split in two and both are shipped: `sizedTo`/`cappedAt`
for the layout sense, and `scaledBy` (a `Relation.Op` division) for the numeric one, with
`VarianceStyling.e` spelling out that the scale is relational and the format is presentational.
Recorded because the brief's phrasing is a natural misreading of the module's name.

---

## 7. Post-review corrections — 2026-09-07

Verdict on the first draft: **FIX-THEN-ADVANCE** (`tracker/loopmodel/E4-REVIEW.md`, findings
M-1 … M-17). The Ermine loaded, the negatives matched verbatim and the differential was clean;
what was wrong was prose, data and census. Everything below was re-measured after the changes,
one JVM at a time, on the final bytes. Sections 1–6 above have been rewritten in place; this
section is the audit trail.

### 7.0 WHICH COMPILER EACH MEASUREMENT WAS TAKEN ON — read this first

The reviewer flagged that at 03:30 on 2026-09-07 someone recompiled the compiler with an
**uncommitted change to `Subst.scala`** (stage S3): `NormalPart` gets a `hashCode` consistent
with its `equals`, and the `a <- (a)` tautology is deleted from published residuals. The
compiled classes carry it — `core/target/scala-3.3.8/classes/.../Subst*.class` are dated 03:56
— and every measurement in this section was taken **after** that, so:

* **§1–§6 above, and the first draft's numbers, are PRE-S3.** They were taken on 2026-09-07
  between 01:00 and 02:15.
* **§7's numbers — the re-run gates, the census, the ladder — are POST-S3.** Taken 03:58–04:20.

Re-measured directly against the new build, with each body alone in a module:

```
scaledBy   : (Relation.Op.AsOp b, PrimitiveNum a) => a -> b c a -> Op c a      -- c <- (c) GONE
outOfRange : (exists (AsOp: d) (AsOp1: d) (e: rho). RelationalComb b, Primitive a,
              AsOp1 opl, c1 <- (c, e), AsOp1 Op, AsOp Op, AsOp opl) => …       -- c <- (c) GONE
unreconciled : 11 existentials, 13 constraints, 8 partitions                   -- was 14 / 9
styledBy, hiddenBy : (exists (AsOp: b). AsOp op, …)                            -- UNCHANGED
```

So S3 removes the tautology as advertised and does **not** touch the existential class defect
(§4.3), and `Present/Signatures.e` still compiles unchanged — a signature carrying a
true-but-redundant constraint is still legal, so `taut`, `scaledByFull` and `unreconciledFull`
all still check and their entailment proofs still hold. `Signatures.e`'s header now says so and
labels its quoted sets as the pre-S3 residuals. Nothing in this group needs to change if S3 is
committed; the commentary is already written for both sides.

**One thing this does invalidate**, and it is worth the orchestrator knowing: the *census* in
§G3 is not directly comparable, solve for solve, with E2's and E3's, which were measured before
S3. The differential is unaffected (the model replays whatever the compiler did, and agrees).

### 7.1 The data — every stated number now comes from the data (M-8)

Four modules stated headline numbers that their own fact tables contradict. Three of the four
are now **computed** with `scanRelation` so they cannot drift again; the fourth is a literal
block whose whole point is to be literal, and its literals were corrected and annotated with
their derivations.

| module | binding | first draft | correct | how it is fixed |
|---|---|---|---|---|
| `SalesDashboard.e` | `kpiRow` net revenue | `1103283.6` | **482,408.30** | computed: `scanRelation` + `sum'` |
| `SalesDashboard.e` | `kpiRow` average order | `73552.2` | **32,160.55** | computed: total / row count |
| `SalesDashboard.e` | `kpiRow` orders | `15` | 15 ✔ | computed: `length rows` |
| `VarianceStyling.e` | `tile "Budget $000"` | `1568.0` | **2,432.0** | computed: `scanRelation` |
| `VarianceStyling.e` | `tile "Actual $000"` | `1680.0` | **2,579.4** | computed |
| `VarianceStyling.e` | `tile "Variance $000"` | `112.0` | **147.4** | computed |
| `AtomicAndRelation.e` | `staticSummary` largest share | `0.184` (the FIRST row's share) | **0.226** | literal, corrected + derivation documented |
| `AtomicAndRelation.e` | `staticSummary` / `twoUp` cost per sample | `11.5952` | **11.5954** | literal (= 10,000,000 / 862,411) |
| `AtomicAndRelation.e` | `acrossTheTop` measurands / labs | `9` / `11` | **11** / **12** | literal, counted |
| `AtomicAndRelation.e` | "four … under one per cent" | four | **three** | prose |
| `StyleGridHeatmap.e` | `impactTree` root | `18130000.0` | **17,230,000.0** | data, = the six children, = the register's category totals |

**The group's own rendering route is the derivation.** `tracker/tools/sql-render.sh`, re-run on
the final bytes (`names: 9 asked, 9 answered, 9 produced SQL`), executes `SalesDashboard`'s own
`byRegionQuarter` against SQLite:

```
quarterName | regionName | revenueK
------------+------------+---------
Q1 | AMER | 49.608599999999996      Q1 | APAC | 87.4428     Q1 | EMEA | 83.2032
Q2 | AMER | 92.104                  Q2 | APAC |  7.296      Q2 | EMEA | 78.9708
Q3 | AMER | 60.8188                 Q3 | APAC | 17.9211     Q3 | EMEA |  5.043
(9 rows)                                                    sum = 482.4083 thousand
```

— 482,408.30, on the same page whose first-draft KPI tile read `currency "USD" 1103283.6`. The
group's own executed SQL disproved the group's own headline number, which is exactly the
reviewer's point; the tile is now computed from the same rows.

*(Note for the next stage: the committed `sql-render.sh` requires each query in the `.in` file to
be preceded by a `"@@name"` label line — the older bare-name format silently produces
`names: 0 asked, 0 answered`.)*

Checked by re-deriving every arithmetic invariant in all four fact tables: `units × price =
gross`, `gross − discount = net`, `net − COGS = margin`, `margin / net = marginPct` on all
fifteen `orders` rows; `actual − budget = variance` and `variance / budget = variancePct` on all
fourteen `budgetLines`; `budgetShare` summing to exactly 1.000000 and `annualCost` to exactly
10,000,000 over `sensors`, whose eleven measurand totals equal `slices`' eleven shares to the
last digit; and the sixteen `risks` rows summing by category to the treemap's six children.
The tables were right; the headlines were not.

### 7.2 The census (M-1, M-9)

Two headline claims were wrong, and one of them was the one the brief singled out.

**"Per-key mints, max 12 — the first time the round-7/8 bound of 11 is exceeded" is deleted.**
It was a mislabelled metric, twice over. `--cycle`'s `maxmint` is
`max rep.maxMint mo.length` where `mo = mintOrder s` (`tracker/lean/Rowpartition/Loop/Cycle.lean:407`)
— the size of the **minted-variable vocabulary** at a step, not a per-key count. The per-key
census is `looptrace --replay … --mints`, and over this group its `max` column is **1**. This is
the same mislabelling E3's review recorded as P-18 against a different column; the correction is
now made in the report, the group README and the plan row. `--cycle`'s `maxmint` is reported
below under its real name.

**"Decision nodes (states)" is renamed `steps`**, as P-18 asked.

**The first draft's figures were not the final bytes**, despite a note claiming they were: the
last edit landed after the trace. Everything in §G2/§G3/§G4(b) is re-measured here on the bytes
this stage ships, which now also include two new modules.

### 7.3 Findings narrowed or withdrawn

| finding | first draft | corrected |
|---|---|---|
| §4.1 writers | "exactly one constructor" each | HTML, Json and JsonDebug export **two** each |
| §4.1 writers | "every one of them defines its entry point with the same four lines" | **four of six**; `JavaFX.e` and `PDF.e` have no `harness` entry point (`grep -l function3` returns four modules) |
| §4.1 writers | table listed `jsonFancy`/`jsonDense` as constructors | those are the **entry points**; the constructors are `jsonWriterFancy`/`jsonWriterDense` |
| §4.1 / §6.1 / README | "every constructor of `Scanner` and `Runner` is a database connection" | **false** — `Runners.sqlite : String -> Runner DB` takes a JDBC URL and `jdbc:sqlite::memory:` works with the driver already on this classpath. The missing piece is one **writer jar**, not a database |
| §4.3 / §6.4 / `Signatures.e` | the existential class appears for five `AsOp` helpers | **three** — `styledBy`, `hiddenBy`, `outOfRange`. `scaledBy` and `unreconciled` infer only real classes; `Signatures.e`'s false `scaledBy` comment is deleted and its header no longer says "four" before listing five |
| §4.9(5) / §6.3 | "no type-level syntax for a record over a concrete row" | **wrong** — `Ord (Record (| positionName |))` loads. Only the `{..r}` sugar needs a variable; the two dropped signatures are **restored** in `SortShowcase.e` |
| §4.2 `.ei` free variable | framed as a property of three helpers | **general**: any universally quantified row variable occurring only in a constraint is printed free |
| §4.7 `Console.other` | "quadratic, and with stdin at EOF, unbounded"; `latest` and `casing` listed as offenders | the loop **cannot terminate** (`readLine` returns `null` at EOF and `null == ""` is false); `latest` and `casing` contain none of the three substrings and exit 0 when piped — both measured |

### 7.4 Coverage gaps closed (M-11, brief item 6)

Four modules the brief named were listed but not exercised. All four now are, for real:

* **`Layout.Scan`** — `SalesDashboard.quarterScanGrid` builds the same quarterly grid as
  `keyedGrid` by the other route (`groupBy1` / `mapV column` / `columns … keys`), which is worth
  having side by side: one decides its schema from a `SoftRelation`, the other from the scanned
  rows.
* **`Layout.PresRow`** — `SalesDashboard.tooltipExtras` / `revenueWithTooltip` use `bar'` at the
  `ExtraMode` signature with a `[...]_PR` bracket, whose `cons_Bracket` carries an `RUnion2`.
* **`Layout.Column.Unsafe`** — `SortShowcase.boxedTable` calls `column#`, the seam between the
  `Column` tree and the writer's `Table#`, with a comment saying that is literally what
  `columnTable` does.
* **`Layout.Report.SelectorMode`** — `DrilldownExplorer.allModes` / `modeName` / `modeUser` write
  out and match on all six constructors and tabulate which stdlib combinator reaches each. The
  first draft's SHAPES block claimed the type was "named directly" when all three occurrences
  were in comments; it is now named for real.

### 7.5 Smaller corrections

* `SalesDashboard.e`'s header said "five charts"; the module builds **eight** chart objects
  (five `chartOf`, one `chartOfAll`, one raw `chart_K`, one `bar'`-with-`PresRow`, one `pieOf` —
  nine after this stage's addition). Header, README and file table now agree (M-13).
* `VarianceStyling.actualPres` presented `varianceK`; renamed **`varianceAmountPres`** (M-14).
* §2's four count claims corrected (M-3): 12 partition-carrying signatures, 15 partition
  constraints, 5 existentials, 14 class constraints.
* The report's list of the costliest solves is re-derived from the new trace (M-15).
* `README.md` gains the three cross-module duplicate names (`shown`, `inRegion`, `byCategory`)
  that the one-session recipe cannot reach unqualified (M-17).
* `Signatures.e` gains a note that **stage S3** (in flight) deletes the `a <- (a)` tautology from
  published residuals, which will make `taut` / `tautIsFree`, `scaledByFull`'s `c <- (c)` member
  and `outOfRange`'s quoted inferred set stale — the written signatures stay legal, the
  commentary will need a revisit (coordinator item 7).
* Corpus size for the record: **354 `.e` files** (the first draft said 333, taken before the
  fifth group landed) — now 356 with this stage's two new modules.

### 7.6 What the corrections added to the group

Two modules, both about the new finding:

* **`core/examples/Present/ProjectionCost.e`** — the ladder, and the pinned form that costs
  nothing. No data, no relation, no presentation: five lambdas and two signatures.
* **`core/examples/Present/shouldfail/proj01_seven_reads.e`** — seven reads of one unannotated
  record, the only module in `core/examples` rejected by the **draw budget** rather than by a
  type error, with the diagnostic recorded verbatim in its header.

Group is now **12** `.e` modules plus **7** negatives, 19 files.

### 7.7 The gates, re-run on the post-review bytes

| gate | first draft | reviewer (pre-correction bytes) | **this run (final bytes)** |
|---|---|---|---|
| G1(a) per file | 10 modules LOADED | 10 LOADED, reproduced | **11 LOADED**, own check 0.18–1.56 s |
| G1(b) batch | 11 modules, 5.93 s | 5.93 s, exact | **12 modules, 10.64 s**, wall 29 s (shared machine) |
| G1(c) negatives | 6 REJECTED, 4 classes | 6 REJECTED, verbatim | **7 REJECTED, 5 classes** — the seventh by the draw budget |
| G2 positives | 126,260 seg, 0/0/0 | 126,756 seg, 0/0/0 | **128,501 seg, 0 skipped / 0 hashdiff / 0 eqdiff** |
| G2 negatives | 59,493 seg, 1 rejected | 59,493 seg, 1 rejected | **59,602 seg, 0/0/0, 2 rejected** |
| G3 census | 2 headline numbers wrong | corrected | re-measured in full, §G3 |
| G4(b) `.ei` | 11 interfaces, round-trips | 11, round-trips | **12 interfaces, 298 signatures**, round-trips |
| G4(c) SQL | 9 relations executed | reproduced exactly | 9 relations executed, values unchanged |

**A new result for the loop-model programme.** The negatives' differential now contains a
**budget stop**, and the Lean model reproduces it at the same draw count:

```
#REJECTED  59601  Row solver budget exhausted at inferImplicitBindingTypes: the loop drew 20009
                  fresh row variables, budget 20000 (-Dermine.solveBudget); …
```

Before this stage the corpus had no segment that exhausted the adopted budget, so the
differential had never checked that the model and the compiler agree about *when the budget
fires*. They do. It is also the slowest segment either side replays — about two minutes in the
model against 2.71 s in the compiler, which is worth knowing before anyone adds a second one.

### 7.8 The re-evaluation

Seven modules re-evaluated in the REPL after the corrections, 29 bindings, **zero errors**. The
four new bindings, with their types:

```
>> boxedTable          : Table# EAtomic# Relation#                       -- Column.Unsafe's column#
>> allModes            : List SelectorMode                               -- all six constructors
>> byPointsRecordOrd   : Record (|pointsScored|) -> Record (|pointsScored|) -> Ordering
                                                                         -- the restored signature
>> viaInference        : String = "abcdef"                               -- proj6 sample
>> viaSignature        : String = "abcdef"                               -- proj6Pinned sample
```

The last pair is the finding in two lines: the same answer, from the same body, at 6,804 draws
and at none.

