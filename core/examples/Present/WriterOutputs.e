module Present.WriterOutputs where

{- WRITING A REPORT OUT: the params -> report -> document pipeline, generic in
   the writer, plus the one form of output this repository CAN actually produce.

   Fact: subscriptions (15 fields: subId, accountCode, accountName, segmentName,
         regionName, planName, billingTerm, termStart, termEnd, monthlyRevenue,
         annualValue, subStatus, ownerRep, channelName, seatCount)

   WHY THIS FILE EXISTS. `Layout.Writer`, `Layout.Writer.Profiled` and
   `Layout.harness` are how a `Report` becomes a document, and none of them had
   an example. They are also the part of the language a reader is most likely to
   get wrong, because the answer to "how do I print this?" is not a function --
   it is an ARCHITECTURE, and it is worth stating exactly.

   ---------------------------------------------------------------------------
   THE PIPELINE, in full

       Report f z                       what the other modules in this directory build
       Writer f z                       an interpreter for reports, in medium `f`, producing `z`
       Scanner f                        executes relations against a database
       Runner f                         runs the `f` effects
       harness' : (SMEnv DB -> Scanner f) -> Runner f
               -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO z

   A `Writer f z` is a FOREIGN type: `Layout/Writer.e` declares
   `foreign data "com.clarifi.reporting.writers.Writer" Writer (f : * -> *) a`
   and gives it a `Functor`, an `Ap` and a `Monad` over `f`, plus `runW` to push
   the finished `z` out as `IO ()`. It declares NO constructor. Every constructor
   lives in the separate `ermine-writers` project, and each one is a Scala
   `function` binding of exactly one shape:

       function "com.clarifi.reporting.writers.HTMLWriter" "htmlWriterRemote"
         htmlWriterRemote : Scanner f -> Runner f -> Writer f HJS

   The writers that exist there, and what each produces:

     Layout.Writer.HTML       `html` / `htmlLocal`      HJS -- HTML + JS; remote
                              mode has charts and tables fetch their own data,
                              local mode inlines it
     Layout.Writer.JavaFX     JavaFX scene graph
     Layout.Writer.Json       `jsonFancy` / `jsonDense`  a JSON document
     Layout.Writer.JsonDebug  `jsonFancy` / `jsonDense`  JSON with layout debug
     Layout.Writer.Csv        `csv`                      one CSV per table
     Layout.Writer.PDF        `pdfWriter ro path`        PDF, via the HTML writer

   And every one of them defines its entry point with the SAME four lines:

       runHtml w f = function3 $ scanner runner params ->
                       unsafePerformIO $ harness' scanner runner w (f params)

   `written` in `Helpers.e` is that, written once. So a production report module
   is a FUNCTION FROM ITS PARAMETERS, and the writer is chosen at the boundary,
   not in the report. That is the production shape of `tracker/JSON-API-DESIGN.md`.

   ---------------------------------------------------------------------------
   WHAT CAN ACTUALLY BE PRODUCED HERE

   None of the above: no concrete writer is on this build's classpath, and both
   `Scanner` and `Runner` constructors are database connections. What DOES run,
   with no database at all, is `Scanners.dumpQuery`, which compiles a relation to
   SQL and hands back the string. That is a real rendering of the RELATIONAL half
   of a report -- join, filter, project, group, order -- and the bindings at the
   bottom of this module produce it. `tracker/tools/sql-render.sh` then executes
   that SQL against SQLite. Its limits, all measured in
   `tracker/loopmodel/E1-EXAMPLES.md` section 7: a `Mem` cannot be dumped, a
   window function only emits through the MS SQL emitter, and a pivot panics.

   SHAPES EXERCISED
     * `written` / `writtenProfiled` from `Helpers.e`, instantiated at a
       three-field parameter record and left polymorphic in the writer.
     * `Layout.harness`, `harness'`, `harnessNoSM`, `harnessNoSM'` -- all four,
       with their types spelled out.
     * `Layout.Writer.Profiled.withProfiling`: a writer transformer that does not
       change the writer's type, hence can be inserted without touching a report.
     * `Layout.Writer`'s `writerFunctor` / `writerAp` / `writerMonad` / `runW`.
     * `Scanners.dumpQuery` and `Scanners.dumpQueryInOrder` against `sqlite` and
       `sqlServer`, with `Relation.Sort` supplying the order.
     * A report that is a FUNCTION of its parameters, with the parameters coming
       from a record rather than being baked in.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/WriterOutputs.e
     >> summaryFor { pRegion = "EMEA", pMinValue = 50000.0, pTitle = "EMEA book" }
     >> sqlOfActive
     >> sqlOfSummary

   The last two print real SQL. Everything else prints its type.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Writer as W
import Layout.Writer.Profiled as WP
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Internal.SMEnv
import Native.Function
import Relation.Op as Op
import Relation.Aggregate as Agg
import Relation.Predicate as Pred
import Relation.Sort as Sort
import Syntax.Relation
import Present.Helpers

field subId, seatCount : Int
field accountCode, accountName, segmentName, regionName : String
field planName, billingTerm, subStatus, ownerRep, channelName : String
field termStart, termEnd : Date
field monthlyRevenue, annualValue : Double

field pRegion, pTitle : String
field pMinValue : Double
field bookValue, accounts : Double

-- ------------------------------------------------------------- the fact table

-- Fifteen columns, twelve subscriptions.
subscriptions : [ subId, accountCode, accountName, segmentName, regionName
                , planName, billingTerm, termStart, termEnd, monthlyRevenue
                , annualValue, subStatus, ownerRep, channelName, seatCount ]
subscriptions = relation [
  { subId = 1, accountCode = "ACC-2001", accountName = "Northwind Traders", segmentName = "Enterprise",
    regionName = "AMER", planName = "Platform", billingTerm = "Annual", termStart = @2011/1/1,
    termEnd = @2011/12/31, monthlyRevenue = 18400.0, annualValue = 220800.0, subStatus = "Active",
    ownerRep = "j.okafor", channelName = "Direct", seatCount = 240 },
  { subId = 2, accountCode = "ACC-2002", accountName = "Wide World Importers", segmentName = "Mid-market",
    regionName = "EMEA", planName = "Business", billingTerm = "Monthly", termStart = @2011/2/1,
    termEnd = @2012/1/31, monthlyRevenue = 4900.0, annualValue = 58800.0, subStatus = "Active",
    ownerRep = "m.lindqvist", channelName = "Partner", seatCount = 70 },
  { subId = 3, accountCode = "ACC-2003", accountName = "Contoso GmbH", segmentName = "Enterprise",
    regionName = "EMEA", planName = "Platform", billingTerm = "Annual", termStart = @2011/2/8,
    termEnd = @2012/2/7, monthlyRevenue = 9750.0, annualValue = 117000.0, subStatus = "Active",
    ownerRep = "m.lindqvist", channelName = "Partner", seatCount = 130 },
  { subId = 4, accountCode = "ACC-2004", accountName = "Adatum Media", segmentName = "Mid-market",
    regionName = "AMER", planName = "Business", billingTerm = "Monthly", termStart = @2011/2/17,
    termEnd = @2012/2/16, monthlyRevenue = 3150.0, annualValue = 37800.0, subStatus = "Churned",
    ownerRep = "s.ahmed", channelName = "Self-serve", seatCount = 45 },
  { subId = 5, accountCode = "ACC-2005", accountName = "Litware Bank", segmentName = "Enterprise",
    regionName = "EMEA", planName = "Platform", billingTerm = "Annual", termStart = @2011/2/23,
    termEnd = @2012/2/22, monthlyRevenue = 24800.0, annualValue = 297600.0, subStatus = "Active",
    ownerRep = "a.petrova", channelName = "Direct", seatCount = 310 },
  { subId = 6, accountCode = "ACC-2006", accountName = "Fabrikam Ltd", segmentName = "SMB",
    regionName = "EMEA", planName = "Team", billingTerm = "Monthly", termStart = @2011/4/5,
    termEnd = @2012/4/4, monthlyRevenue = 1875.0, annualValue = 22500.0, subStatus = "Churned",
    ownerRep = "a.petrova", channelName = "Self-serve", seatCount = 25 },
  { subId = 7, accountCode = "ACC-2007", accountName = "Trey Logistics", segmentName = "Enterprise",
    regionName = "EMEA", planName = "Platform", billingTerm = "Annual", termStart = @2011/4/24,
    termEnd = @2012/4/23, monthlyRevenue = 12375.0, annualValue = 148500.0, subStatus = "Active",
    ownerRep = "m.lindqvist", channelName = "Direct", seatCount = 165 },
  { subId = 8, accountCode = "ACC-2008", accountName = "Proseware Health", segmentName = "Mid-market",
    regionName = "APAC", planName = "Business", billingTerm = "Quarterly", termStart = @2011/5/2,
    termEnd = @2012/5/1, monthlyRevenue = 6400.0, annualValue = 76800.0, subStatus = "Active",
    ownerRep = "h.kim", channelName = "Partner", seatCount = 95 },
  { subId = 9, accountCode = "ACC-2009", accountName = "Tailspin Air", segmentName = "SMB",
    regionName = "APAC", planName = "Team", billingTerm = "Monthly", termStart = @2011/6/13,
    termEnd = @2012/6/12, monthlyRevenue = 1450.0, annualValue = 17400.0, subStatus = "Active",
    ownerRep = "h.kim", channelName = "Self-serve", seatCount = 20 },
  { subId = 10, accountCode = "ACC-2010", accountName = "Woodgrove Capital", segmentName = "Enterprise",
    regionName = "AMER", planName = "Platform", billingTerm = "Annual", termStart = @2011/7/1,
    termEnd = @2012/6/30, monthlyRevenue = 31200.0, annualValue = 374400.0, subStatus = "Active",
    ownerRep = "j.okafor", channelName = "Direct", seatCount = 400 },
  { subId = 11, accountCode = "ACC-2011", accountName = "Coho Vineyard", segmentName = "SMB",
    regionName = "AMER", planName = "Team", billingTerm = "Monthly", termStart = @2011/8/9,
    termEnd = @2012/8/8, monthlyRevenue = 980.0, annualValue = 11760.0, subStatus = "Churned",
    ownerRep = "s.ahmed", channelName = "Self-serve", seatCount = 12 },
  { subId = 12, accountCode = "ACC-2012", accountName = "Alpine Ski House", segmentName = "Mid-market",
    regionName = "EMEA", planName = "Business", billingTerm = "Quarterly", termStart = @2011/9/1,
    termEnd = @2012/8/31, monthlyRevenue = 5300.0, annualValue = 63600.0, subStatus = "Active",
    ownerRep = "a.petrova", channelName = "Partner", seatCount = 68 }]

-- ============================================ the report, as a function of params

-- The parameter record. In production these arrive from the request; here they
-- are just a record, and the type of `reportFor` says exactly which fields a
-- caller must supply. `Present/ValidationReport.e` shows the other half: turning
-- the request's STRINGS into this record, with errors accumulated.
active   = subscriptions |> filterEq subStatus "Active"
inRegion r = if (r == "Global") active (active |> filterEq regionName r)
aboveValue v r = r |> filter_Pred (annualValue >=_Pred prim_Op v)

bookLegend : Legend_Lg (| accountName, segmentName, planName, billingTerm
                        , ownerRep, monthlyRevenue, annualValue, seatCount |)
bookLegend =
  withFormats ([ (accountName, "Account")  ^ 0
               , (segmentName, "Segment")  ^ 1
               , (planName,    "Plan")     ^ 2
               , (billingTerm, "Term")     ^ 3
               , (ownerRep,    "Owner")    ^ 4 ]_Sorted_Lg)
              (currency_Fmt "USD")
              { monthlyRevenue, annualValue, seatCount }

summaryOf r = aggregateByGroup_Agg (sum_Agg (col_Op annualValue)) {segmentName}
                                   bookValue r

-- THE REPORT. One argument, a record; everything else is derived. This is the
-- value a writer is handed.
reportFor p =
  let rows = aboveValue (p ! pMinValue) (inRegion (p ! pRegion))
  in vflow [ h2 (p ! pTitle)
           , textNoMarkdown ("Region "        ++_String (p ! pRegion))
           , textNoMarkdown ("Minimum ACV "   ++_String toString (p ! pMinValue))
           , h3 "By segment"
           , tabular Nothing (summaryOf rows)
           , h3 "Every subscription"
           , tabular_K ([tabLegend_O := bookLegend]_Opt)
                       (rows # { accountName, segmentName, planName, billingTerm
                               , ownerRep, monthlyRevenue, annualValue, seatCount }) ]

summaryFor p = summaryOf (aboveValue (p ! pMinValue) (inRegion (p ! pRegion)))

-- ================================================= handing it to a writer

-- Generic in the writer. Instantiating `w` is a one-line module in
-- `ermine-writers`; nothing else changes. The result is a `Function3` because
-- that is what the report server calls.
asDocument w = written w reportFor

-- The same with per-scan timing. `withProfiling` is a `WriterCtor f c ->
-- WriterCtor f c`, so it slots in without disturbing anything downstream.
asProfiledDocument w = writtenProfiled w reportFor

-- The four harness forms, with their differences spelled out. `harness` runs the
-- report and then pushes the result out through `runW`, giving `IO ()`;
-- `harness'` stops one step earlier and hands back the `z`, which is what an
-- embedding caller wants. The `NoSM` pair skip the security-master environment
-- and use the cached one, which is what a test harness wants.
runAndEmit    : forall f z. (SMEnv DB -> Scanner f) -> Runner f
             -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO ()
runAndEmit    = harness

runAndReturn  : forall f z. (SMEnv DB -> Scanner f) -> Runner f
             -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO z
runAndReturn  = harness'

runCachedEmit : forall f z. (SMEnv DB -> Scanner f) -> Runner f
             -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO ()
runCachedEmit = harnessNoSM

runCachedRet  : forall f z. (SMEnv DB -> Scanner f) -> Runner f
             -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO z
runCachedRet  = harnessNoSM'

-- `Writer`'s own algebra, over the medium `f`. A writer is not just a sink: the
-- report interpreter needs to sequence effects in `f`, and these are how.
writerF w = writerFunctor w
writerA w = writerAp w
writerM w = writerMonad w
emit w z  = runW w z

-- `SelectorEvent` composition, which is the other half of `Layout.Writer`'s
-- public surface: `live` is the event that has already fired, and `orEvent`
-- merges two streams. The selector combinators in `Present/DrilldownExplorer.e`
-- are built on exactly these.
alwaysNow = live
either2 a b = orEvent a b

-- ======================================== what this repository CAN emit: SQL

-- `dumpQuery` compiles a relation to SQL for a given dialect. It needs a
-- `Scanner`, but not a live connection -- the scanner is only asked for its
-- emitter. This is the nearest thing to `render` that works from `bin/ermine`,
-- and `tracker/tools/sql-render.sh` executes the result against SQLite.
lite = sqlite_Scanners cachedSMEnv
mss  = sqlServer_Scanners cachedSMEnv

sqlOfActive  = unsafePerformIO (dumpQuery_Scanners lite active)
sqlOfEmea    = unsafePerformIO (dumpQuery_Scanners lite (inRegion "EMEA"))
sqlOfSummary = unsafePerformIO (dumpQuery_Scanners lite (summaryOf active))

-- With an explicit ORDER BY. `Relation.Sort.ordering` builds the sort from a
-- row -- and note the signature: `dumpQueryInOrder : Scanner f -> rel r -> Sort r
-- -> IO String` wants a `Sort` over the WHOLE row, not a sub-row, so the
-- relation is projected to exactly the columns being sorted on. (`Sort.only`
-- and `Sort.reorder` are the combinators for the other direction.)
ordered = active # { accountName, annualValue }
sqlOfOrdered =
  unsafePerformIO (dumpQueryInOrder_Scanners lite ordered
                     (ordering_Sort {accountName, annualValue}))

-- The MS SQL emitter, for comparison: the only one that emits window functions
-- (`SqlEmitter.emitOver` is a stub on every other dialect --
-- `tracker/loopmodel/E1-EXAMPLES.md` section 7.3).
sqlOfActiveMss = unsafePerformIO (dumpQuery_Scanners mss active)

-- ==================================================================== the page

writerOutputs = reportFor { pRegion = "EMEA", pMinValue = 50000.0
                          , pTitle = "EMEA book, ACV at least $50k" }
