module Present.Helpers where

{- THIRTY-FOUR GENERIC PRESENTATION HELPERS: legends, formats, conditional styling, sort
   strategies, magnitudes, charts, grids, drilldowns, validation and writers.

   `core/examples/Present` is about the half of Ermine that turns a relation into
   a DOCUMENT. That half is row-polymorphic too, and much less obviously so than
   the relational half: a legend, a sort strategy and a chart series each carry a
   row, and combining two of them is a row PARTITION exactly like a join is.
   Read `r <- (k, m)` as "the row r is exactly the disjoint union of k and m";
   every helper below that combines two presentational objects carries one.

   ---------------------------------------------------------------------------
   THE FOUR ROWS A REPORT CARRIES, and which type says so

     Legend r          the columns a grid shows, in order, with labels
     SortStrategy r     how a presentation's own columns reorder the underlying sort
     Presentation r a   how ONE datum (over the columns r) is drawn
     ChartSeries xa ya  a series; its rows are hidden inside the existential

   `Layout.Legend.(++)`, `Layout.SortStrategy.(++)` and `Layout.Column.join` are
   all partitions; the helpers here are thin, well-typed names for them.

   ---------------------------------------------------------------------------
   THE OTHER RULE, and it is the expensive one: WRITE THE PARAMETER ROW DOWN

   `Record.(!)` is a row partition, not a lookup:
   `(!) : t <- (r, s) => {..t} -> Field r a -> a`. So a report that reads N
   fields out of one UNANNOTATED parameter record hands the solver N partitions
   sharing a left-hand side, and closing them costs FIVE times as much per
   additional field -- exactly `(5^N - 3*3^N + 2*2^N)/2` draws:
   **3 / 30 / 207 / 1,230 / 6,783 for N = 2…6, and seven reads exhaust the adopted
   20,000-draw budget** (they need 35,910). The same five reads under one written
   partition cost **nothing at all**.

   `Present/ProjectionCost.e` measures this and
   `Present/shouldfail/proj01_seven_reads.e` is the module that does not
   compile. It is the shape this whole directory is about -- params to report --
   so it is the first thing to know before writing one.

   ---------------------------------------------------------------------------
   THE RULE THIS FILE OBEYS, inherited from `Ai/Common.e` and `Time/Helpers.e`

   A row-polymorphic helper is only useful if its CALL SITES check. The Ai
   README's cliff -- bundling `if`'s `RUnion3` on top of `combine`'s `RUnion2`
   into one signature -- does not reproduce at the row-solver defaults adopted at
   `fe024a7`; `Layout.Report.Fulcrum.Legendary`'s `snoc_Brace`, which carries a
   `RUnion2` per pivot column, is chained four deep in `FulcrumPanel.e` and costs
   nothing measurable. See `tracker/loopmodel/E4-EXAMPLES.md` section 4.

   ---------------------------------------------------------------------------
   WHAT YOU CANNOT DO FROM `bin/ermine`, and why the headers say what they say

   There is NO `render`. Running a `Report` needs a `Layout.Writer`, and every
   concrete writer (HTML, JavaFX, JSON, JsonDebug, CSV, PDF) lives in the
   separate `ermine-writers` project, which is not on this build's classpath;
   `Layout.harness` additionally needs a `Scanner` and a `Runner`, and every
   constructor of both is a database connection. So from the REPL you EVALUATE a
   report, which prints `Report <function>`, and you evaluate the RELATIONS it
   draws, which prints their resolved headers -- the column set the document
   will show. `written` below is the writer-generic entry point, and it is the
   exact shape every writer in `ermine-writers` uses; it type-checks here and
   cannot be run here.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Column as Col
import Layout.Magnitude
import Layout.Color
import Layout.Font
import Layout.SortStrategy as SS
import Layout.SortPriority
import Layout.Validation as V
import Layout.Writer as W
import Layout.Writer.Profiled as WP
import Layout.Report.Fulcrum.Dynamic as DF
import Layout.Report.SoftRelation as SR
import DrilldownList as DDL
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Sort as Sort
import Internal.SMEnv
import Native.Function
import Validation as Vd
import Syntax.Relation
import Syntax.List

-- ==================================================================== legends

-- | The default legend for a row: every column, natural order, unsorted, no
-- special format. The identity of the legend world -- `legendRow . legendFor`
-- is the row you started with -- and the thing to reach for when a grid should
-- simply show what the relation has.
legendFor : forall r. Row r -> Legend_Lg r
legendFor = fromRow_Lg

-- | A legend for the KEY columns, plus one `Format` applied to EVERY measure
-- column, whatever those happen to be.
--
-- This is the generic form of "the identifiers on the left, the money on the
-- right, all of it in dollars". The partition `r <- (k, m)` is what makes it
-- generic: the caller supplies a legend over the keys and a `Row` over the
-- measures, and the solver checks that together they are exactly the row the
-- grid will show -- no column shown twice, none left out.
withFormats : forall k m r a. (r <- (k, m))
           => Legend_Lg k -> Format_Fmt a -> Row m -> Legend_Lg r
withFormats klg fmt mrow = klg ++_Lg fromRowWithFormat_Lg fmt mrow

-- | Cons one labelled, presented column onto a legend. `Layout.Legend` gives
-- this as the `[...]_Simple_Lg` bracket syntax; as a function it composes, so a
-- legend can be built by a fold over a list of columns.
--
-- The partition `t <- (r, s)` says the new column is NOT already in the legend.
labelled : forall r s t a pr. (t <- (r, s), AsPresentation pr)
        => pr r a -> String -> Legend_Lg s -> Legend_Lg t
labelled pr lbl rest = legend_Lg pr lbl ++_Lg rest

-- | Put a legend's columns under one spanning heading:
--
--       |     Fiscal 2011     |
--       |  Q1 |  Q2 |  Q3 | Q4 |
--
-- The row is untouched -- grouping is presentation, not schema -- which is why
-- there is no partition here.
groupedAs : forall r. String -> Legend_Lg r -> Legend_Lg r
groupedAs = legendGroup_Lg

-- | Rename every column of a row for display, by a function on the column name.
-- Useful when the database names are `amt_usd_ttm` and the reader wants
-- "Amount (USD, TTM)".
relabelled : forall r. (String -> String) -> Row r -> Legend_Lg r
relabelled = fromRowWithDisplayFunc_Lg

-- | Move one already-labelled column to a new position in the INITIAL sort of a
-- grid, leaving everything else alone. The label is the display label, not the
-- column name, because that is what the writer sorts by.
pinned : forall r. String -> SortPriority -> Legend_Lg r -> Legend_Lg r
pinned = reprioritizeLabel_Lg

-- | A column that participates in the sort but is NOT drawn -- the classic
-- "sort by the numeric month, show the month name" trick. The legend's row is
-- the hidden column alone, so a caller combines it with `++_Lg` and the
-- partition tells the solver the hidden column is really there.
hiddenBy : forall r a op. AsOp op => op r a -> SortPriority -> Legend_Lg r
hiddenBy op sp = exoticHidden_Lg op (sortBy_SS forward_SS (asOp_Op op)) sp

-- ============================================================== presentations

-- | Draw a number in one of two colours according to a threshold: at or above
-- `t` in `good`, below it in `bad`.
--
-- Row-polymorphic in `v`, the columns the underlying `Op` reads, so it applies
-- equally to a bare field, to a computed difference and to a ratio. This is the
-- generic conditional-format rule; `Layout.Format.conditional` is the mechanism
-- and `Layout.Format.colored` is the paint.
styledBy : forall v n op. (AsOp op, PrimitiveNum n)
        => n -> Color -> Color -> Format_Fmt n -> op v n -> Presentation_Pres v n
styledBy t good bad f =
  presentation_Pres (conditional_Fmt (gteCondition_Fmt t) (colored_Fmt good white f)
                                                          (colored_Fmt bad white f))

-- | The three-band form: below `lo` in `bad`, at or above `hi` in `good`,
-- between them in `mid`. Nested `conditional`s -- `Format` is a tree, so the
-- bands nest rather than needing a list.
bandedBy : forall v n op. (AsOp op, PrimitiveNum n)
        => n -> n -> Color -> Color -> Color -> Format_Fmt n
        -> op v n -> Presentation_Pres v n
bandedBy lo hi bad mid good f =
  presentation_Pres
    (conditional_Fmt (gteCondition_Fmt hi) (colored_Fmt good white f)
      (conditional_Fmt (ltCondition_Fmt lo) (colored_Fmt bad white f)
                                            (colored_Fmt mid white f)))

-- | Accounting style: negatives in parentheses rather than with a minus sign,
-- rounded to `n` places, and coloured by the writer when it can.
accounting : forall n. PrimitiveNum n => Int -> Format_Fmt n
accounting = roundParens'_Fmt True

-- | A lookup table over a string column: show "AMER" as "Americas" without
-- putting the long name in the database. `Format.alias` is a Format rather than
-- an `Op`, so the RELATION still carries the code -- filters and joins keep
-- working on the short value.
aliasedBy : forall v op. AsOp op
         => List (String, String) -> op v String -> Presentation_Pres v String
aliasedBy tbl = presentation_Pres (alias_Fmt tbl)

-- ================================================================== sorting

-- | Sort by one presentation's columns, then by another's, each in its own
-- direction. `SortStrategy` is RELATIVE (see the header of
-- `Layout.SortStrategy`): `reverse` does not mean descending, it means "the
-- opposite of whatever the grid's own sort says".
--
-- The partition `t <- (r, s)` is the whole content of the combinator: two
-- strategies compose only if they talk about disjoint columns.
sortedBy : forall r s t a b p1 p2. (t <- (r, s), AsPresentation p1, AsPresentation p2)
        => SortDirection_SS -> p1 r a -> SortDirection_SS -> p2 s b
        -> SortStrategy_SS t
sortedBy d1 a d2 b = sortBy_SS d1 a ++_SS sortBy_SS d2 b

-- | The one-column strategy, reversed. Named because `sortBy reverse` reads
-- like "descending" and is not.
againstBy : forall r a pr. AsPresentation pr => pr r a -> SortStrategy_SS r
againstBy = sortBy_SS reverse_SS

-- ======================================================== magnitudes and size

-- | Fix a report's PREFERRED width and height. `Layout.Magnitude` is about the
-- size of a box on a page -- cells, pixels, or a dimensionless weight -- and has
-- nothing to do with scaling a number; for that see `scaledBy` below.
sizedTo : forall f z. MagnitudeList -> MagnitudeList -> Report f z -> Report f z
sizedTo w h = prefW w . prefH h

-- | Cap a report's size, rather than suggesting it.
cappedAt : forall f z. List Area -> Report f z -> Report f z
cappedAt = maxA

-- | Lay reports out side by side in the given proportions. Two panels at 2:1
-- is `spread [(2.0, big), (1.0, small)]`.
spread : forall f z. List (Double, Report f z) -> Report f z
spread = hspanWeighted'

-- | Divide a measure by a constant, keeping the row it reads. THIS is "in
-- thousands" / "in millions": the relation carries the scaled number and the
-- legend's `Format` says how many places to show. Row-polymorphic in `v`.
scaledBy : forall v n op. (AsOp op, PrimitiveNum n) => n -> op v n -> Op_Op v n
scaledBy k o = asOp_Op o /_Op prim_Op k

-- =================================================================== charts

-- | A titled chart of one series, generic in the SERIES MODE: pass `bar`,
-- `line`, `step`, `scatter`, `stackedBar` or `stackedArea` and it draws that.
--
-- The mode's own type is rank-2 (`Layout.Chart.ChartMode`), so it is taken here
-- monomorphically -- exactly as the stdlib's own `Layout.Report.series` does --
-- and instantiated afresh at each call site. The existential `o` in the
-- constraint is what lets a caller pass a 20-column fact table for a chart that
-- reads three of its columns: `r <- (sr, xr, yr, o)` says "series, category and
-- value, plus whatever else you have".
chartOf : forall s x y r sr xr yr sa xa ya rel f z.
          (exists o. AsPresentation s, AsOp x, AsOp y, r <- (sr, xr, yr, o),
                     Relational rel, Primitive xa, Primitive ya)
       => String -> Axis xa -> Axis ya
       -> (s sr sa -> x xr xa -> y yr ya -> rel (|..r|) -> ChartSeries xa ya)
       -> s sr sa -> x xr xa -> y yr ya -> rel (|..r|) -> Report f z
chartOf title xax yax mode s x y rel =
  chart_K ([chartTitle_O := title]_Opt) xax yax [mode s x y rel]

-- | Several series on one pair of axes -- the comparison chart. The series list
-- is built by the caller (usually `[bar s x y actual, line s x y forecast]`),
-- which is what keeps the modes independent.
chartOfAll : forall xa ya f z. (Primitive xa, Primitive ya)
          => String -> Axis xa -> Axis ya -> List (ChartSeries xa ya) -> Report f z
chartOfAll title xax yax series =
  chart_K ([chartTitle_O := title]_Opt) xax yax series

-- | A pie chart of a label column against a measure column. The partition
-- `r <- (labels, value, o)` carries the rest of the fact row through untouched.
pieOf : forall labels value r l d z rel prl prv f.
        (exists o. r <- (labels, value, o), Relational rel,
                   AsPresentation prl, AsPresentation prv, PrimitiveNum d)
     => String -> prl labels l -> prv value d -> rel (|..r|) -> Report f z
pieOf title lbl v = pieChart_K ([pieTitle_O := title]_Opt) lbl v

-- ==================================================================== grids

-- | A grid keyed by `k`, with the columns named by whatever DISTINCT VALUES the
-- key column has -- the "soft schema" grid. `Layout.Report.SoftRelation` calls
-- the pair a `SoftRelation`; this builds the common case, where every value
-- column gets the same presentation and no special sort.
--
-- The `{..k} -> ...` function is the dependent part: the column set is not known
-- until the data is scanned.
softGrid : forall k v a b prk prv.
           (exists o. o <- (k, v), AsPresentation prk, AsPresentation prv)
        => prk k a -> prv v b -> SoftRelation_SR a b k v
softGrid pk pv =
  softRelation pk (Left (ordering_Pres Ascending_Sort pk))
                  (_ -> unsorted (pv, Nothing))

-- | Draw a soft-schema grid: the identifier columns on the left under `ilg`,
-- then one column per distinct key value. `r <- (k, v, i)` is a THREE-part
-- partition -- key columns, value columns, identifier columns -- and every
-- column of the fact table must land in exactly one of them.
keyedGrid : forall r k v i a b f z rel. (r <- (k, v, i), Relational rel)
         => SoftRelation_SR a b k v -> Legend_Lg i -> rel (|..r|) -> Report f z
keyedGrid sr ilg = keyValueTabular sr (Just ilg)

-- | A fulcrum: one column per key value, like `keyedGrid`, but with the column's
-- name, format and underlying `Op` chosen per key. `Layout.Report.Fulcrum.Dynamic`
-- calls the per-key result a `PivotColumn`.
fulcrumOf : forall k v. Row k -> ({..k} -> PivotColumn_DF v) -> DynamicFulcrum_DF k v
fulcrumOf kr f = DynamicFulcrum_DF kr (Left (ordering_Sort kr)) f

-- ============================================================== drilldowns

-- | A tree grid: rows nest under their parents, and the label column is moved
-- to the left. `v <- (label, o)` says the label is one of the displayed columns.
drilldownOf : forall r r1 r2 id v label f z rel.
              (exists o. r <- (r1, r2, v), v <- (label, o), Relational rel)
           => Legend_Lg v -> Field label String -> Field r1 id -> Field r2 id
           -> rel (|..r|) -> Report f z
drilldownOf lg = drilldownTable (Just lg)

-- | The multi-level form: a `DrilldownList` names one (parent, child) pair per
-- LEVEL, so a three-level hierarchy is a three-element list, and the second
-- relation gives the roots of the forest.
nestedOf : forall r r1 v label f z rel.
           (exists o. Has r r1, Has r v, v <- (label, o), Relational rel)
        => Legend_Lg v -> Field label String -> DrilldownList_DDL r1
        -> rel (|..r|) -> rel (|..r|) -> Report f z
nestedOf lg = drilldownTable2 (Just lg)

-- ================================================================ validation

-- | Run a form validator over the submitted values; on success draw the report,
-- on failure draw the field-by-field errors as a report of their own.
--
-- `FormValidator r` is `Map String String -> Either (List Err) {..r}`: the row
-- `r` is the record the form PRODUCES, so the same helper serves a two-field
-- filter bar and a twenty-field entry screen.
validated : forall r f z.
            FormValidator_Vd r -> ({..r} -> Report f z) -> Map_Map String String
         -> Report f z
validated = withValidation_V

-- | The rows of a relation whose measure falls OUTSIDE [lo, hi] -- a range check
-- expressed as a relation, so the failures are themselves a report.
-- `r <- (v, o)` carries every other column through, which is what makes the
-- failure report useful: it shows the offending row, not just the value.
outOfRange : forall v o r n. (r <- (v, o), PrimitiveNum n)
          => Field v n -> n -> n -> Relation r -> Relation r
outOfRange f lo hi =
  filter_Pred (f <_Pred prim_Op lo ||_Pred f >_Pred prim_Op hi)

-- | The rows whose key is null. A nullable key is the single most common data
-- defect in a reporting warehouse and the one a join silently swallows.
missingKey : forall h o r a. (r <- (h, o), Primitive a)
          => Field h (Nullable a) -> Relation r -> Relation r
missingKey f = filter_Pred (isNull_Pred (asOp_Op f))

-- | The rows where `part1 + part2` does not reconcile to `total` within
-- `tolerance`. Three named columns and everything else carried: the classic
-- "the components do not add up" check.
unreconciled : forall a b c o r n. (r <- (a, b, c, o), PrimitiveNum n)
            => Field a n -> Field b n -> Field c n -> n -> Relation r -> Relation r
unreconciled p1 p2 total tol =
  filter_Pred (abs_Op (asOp_Op total -_Op (asOp_Op p1 +_Op asOp_Op p2))
                 >_Pred prim_Op tol)

-- ================================================================== writers

-- | THE PRODUCTION ENTRY POINT: params in, document out.
--
-- Every writer in the `ermine-writers` project -- HTML (remote and local),
-- JavaFX, JSON (fancy and dense), JsonDebug, CSV and PDF -- exposes exactly one
-- Ermine-facing constructor of type `Scanner f -> Runner f -> Writer f z`, and
-- exactly one entry point of the shape below. `written` is that entry point,
-- written once and generic in the writer:
--
--     writtenAsHtml = written htmlWriterRemote   -- in ermine-writers
--     writtenAsCsv  = written csvWriter
--
-- The `Function3` is deliberate: the report server calls this from Scala with a
-- scanner constructor, a runner and the request's parameters, and gets back the
-- document. The parameters are a plain `p`, so a report is a FUNCTION from its
-- parameters -- which is the whole production shape (`tracker/JSON-API-DESIGN.md`).
--
-- It type-checks here and cannot RUN here: no concrete writer is on this
-- build's classpath. See the module header.
written : forall f z p.
          (Scanner f -> Runner f -> Writer f z) -> (p -> Report f z)
       -> Function3 (SMEnv DB -> Scanner f) (Runner f) p z
written w f = function3 $ backend runner params ->
  unsafePerformIO $ harness' backend runner w (f params)

-- | The same, with `Layout.Writer.Profiled`'s timing wrapper around the writer:
-- every scan the document performs is logged with its wall clock. One
-- combinator, `withProfiling`, and it does not change the writer's type -- which
-- is why it can be slipped in without touching the report.
writtenProfiled : forall f z p.
                  (Scanner f -> Runner f -> Writer f z) -> (p -> Report f z)
               -> Function3 (SMEnv DB -> Scanner f) (Runner f) p z
writtenProfiled w = written (withProfiling_WP w)

-- =================================================================== layout

-- | A titled, boxed panel: the unit a dashboard is made of.
panel : forall f z. String -> Report f z -> Report f z
panel t r = box (titled (text t) (pad2 r))

-- | A big number with a caption under it -- the "KPI tile".
kpi : forall f z. String -> Report f z -> Report f z
kpi capt v = centered (vflow [ style "h3" v, style "h5" (text capt) ])

-- | A dashboard: a grid of panels, each row spread evenly.
dashboard : forall f z. List (List (Report f z)) -> Report f z
dashboard = vflow . map (hspan . map pad1)
