module Present.AtomicAndRelation where

{- THE TWO REPORT MODELS, SIDE BY SIDE: a report built from ATOMS -- literal
   values with formats, laid out by hand -- and a report built from RELATIONS,
   with the layout derived from the data; plus `scanRelation`, the bridge that
   turns one into the other, and `Layout.Report.Relation`, which is the only
   stdlib module that reshapes a relation FOR presentation reasons.

   Fact: sensors (18 fields: sensorId, programmeCode, programmeName, sensorName,
         sensorFamily, measurandName, labCode, unitCode, budgetShare,
         annualCost, unitCost, pointCount, driftPct, gradeCode,
         installDate, checkDate, ownerName, standardName)

   WHY THIS FILE EXISTS. `Layout.Report.Atomic` had one use in `core/examples`
   (`val` inside `GridExample.e`) and `Layout.Report.Relation` had none at all,
   even though the latter solves a problem every pie chart in the world has: a
   long tail of slices too small to draw, which must be summed into "Other"
   WITHOUT changing the total. `cutoffDrilldownRel` does that at every level of a
   drilldown, and it is forty lines of careful relational algebra that nobody
   would think to write.

   THE TWO MODELS

     ATOMIC     `Atomic a = Atomic (Format a) a` -- a value and how to draw it.
                Reports are composed by `atom`, `text`, `number`, `currency`,
                `percent`, `grid`, `valueGrid`, `labeled`, `tabbed`, `tree`, and
                the numbers are in the SOURCE. Good for the summary block at the
                top of a factsheet, where there are eight numbers and each has a
                name; useless for a table of a thousand rows.

     RELATIONAL `tabular`, `columnTable`, `keyValueTabular`, the charts. The
                shape of the output is a function of the data, and the writer
                does the paging, the sorting and the scrolling. Good for the
                table; clumsy for the eight-number block, because every number
                would have to be its own one-row relation.

     THE BRIDGE `scanRelation : rel r -> (List {..r} -> Report f z) -> Report f z`
                executes the relation and hands its rows to a continuation as
                ORDINARY VALUES. That is how an atomic block gets numbers that
                came from data. `scan` / `runScan` are the same thing in
                continuation-monad clothing, so several relations can be scanned
                in a `do` block. This is also, incidentally, how
                `keyValueTabular` discovers its own column set.

   SHAPES EXERCISED
     * `Atomic` built by hand and by `val`; `atom`, `atom'`, `wrapped`, `fmt`,
       `atomShown`, `number`, `wholeNumber`, `currency`, `percent`, `rounded`,
       `text`, `textNoMarkdown`, `textVerbatim`, `labeled`, `dateRange`.
     * `valueGrid`, `valueGridN`, `valueGridR`, `grid`, `hflowLabeled` -- the
       five ways to lay out label/value pairs.
     * `formatDate` and `formatDateRangeFn`: the report asks the WRITER how to
       render a date, because the format string belongs to the medium. This is
       the one place a report is a continuation for a reason that is not
       laziness.
     * `scanRelation`, `scanRelationInOrder`, `scan` + `runScan`: relation to
       values, with and without an order.
     * `Layout.Report.Relation.cutoffDrilldownRel`: the "Other" bucket at every
       level of a hierarchy, preserving the total.
     * `tree` over `Tree`, `tabbed`, `sideTabbed`, `collapsible`,
       `summaryDetail`, `sectionRibbon`, `floatSides`, `hugL`/`hugR`.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/AtomicAndRelation.e
     >> factsheet
     >> withOther
     >> sensors

   There is no `render`; evaluate the report and the relations. See
   `tracker/loopmodel/E4-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Magnitude
import Layout.Report.Relation as RR
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Relation.Op as Op
import Relation.Aggregate as Agg
import Relation.Sort as Sort
import Tree as T
import Syntax.Relation
import Syntax.List
import Present.Helpers

field sensorId, pointCount : Int
field programmeCode, programmeName, sensorName, sensorFamily, measurandName : String
field labCode, unitCode, gradeCode, ownerName, standardName : String
field installDate, checkDate : Date
field budgetShare, annualCost, unitCost, driftPct : Double

field sliceId, sliceParent : Int
field sliceName : String
field sliceWeight : Nullable Double
field measurandCost : Double

-- ------------------------------------------------------------- the fact table

-- Eighteen columns, fourteen sensors, with a deliberate long tail: the bottom
-- four lines are under one per cent each and exist to be bucketed.
sensors : [ sensorId, programmeCode, programmeName, sensorName, sensorFamily
          , measurandName, labCode, unitCode, budgetShare, annualCost, unitCost
          , pointCount, driftPct, gradeCode, installDate, checkDate
          , ownerName, standardName ]
sensors = relation [
  { sensorId = 1, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Northwind thermopile",
    sensorFamily = "Field", measurandName = "Temperature", labCode = "LB-01", unitCode = "K",
    budgetShare = 0.1840, annualCost = 1840000.0, unitCost = 41.20, pointCount = 44660,
    driftPct = 1.80, gradeCode = "AC-1", installDate = @2007/4/2,
    checkDate = @2011/9/30, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 2, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Kestrel pressure cell",
    sensorFamily = "Field", measurandName = "Pressure", labCode = "LB-02", unitCode = "kPa",
    budgetShare = 0.1520, annualCost = 1520000.0, unitCost = 78.50, pointCount = 19363,
    driftPct = 0.90, gradeCode = "AC-2", installDate = @2007/5/14,
    checkDate = @2011/9/30, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 3, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Meridian hygrometer",
    sensorFamily = "Bench", measurandName = "Humidity", labCode = "LB-03", unitCode = "%RH",
    budgetShare = 0.2260, annualCost = 2260000.0, unitCost = 101.40, pointCount = 22288,
    driftPct = 4.25, gradeCode = "AC-0", installDate = @2007/9/3,
    checkDate = @2011/8/26, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 4, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Harbour strain bridge",
    sensorFamily = "Field", measurandName = "Strain", labCode = "LB-04", unitCode = "um/m",
    budgetShare = 0.1110, annualCost = 1110000.0, unitCost = 12.60, pointCount = 88095,
    driftPct = 3.40, gradeCode = "AC-3", installDate = @2008/2/18,
    checkDate = @2011/9/12, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 5, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Aster flow meter",
    sensorFamily = "Field", measurandName = "Flow", labCode = "LB-05", unitCode = "L/min",
    budgetShare = 0.0980, annualCost = 980000.0, unitCost = 33.90, pointCount = 28908,
    driftPct = 4.10, gradeCode = "AC-3", installDate = @2008/6/9,
    checkDate = @2011/7/29, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 6, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Vantage voltmeter",
    sensorFamily = "Field", measurandName = "Voltage", labCode = "LB-06", unitCode = "V",
    budgetShare = 0.0820, annualCost = 820000.0, unitCost = 24.70, pointCount = 33198,
    driftPct = 5.20, gradeCode = "AC-1", installDate = @2008/11/4,
    checkDate = @2011/9/16, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 7, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Cobalt torque cell",
    sensorFamily = "Field", measurandName = "Torque", labCode = "LB-07", unitCode = "N.m",
    budgetShare = 0.0460, annualCost = 460000.0, unitCost = 18.20, pointCount = 25274,
    driftPct = 2.70, gradeCode = "AC-4", installDate = @2009/1/26,
    checkDate = @2011/6/24, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 8, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Pinewood balance",
    sensorFamily = "Field", measurandName = "Mass", labCode = "LB-01", unitCode = "kg",
    budgetShare = 0.0390, annualCost = 390000.0, unitCost = 55.30, pointCount = 7052,
    driftPct = 6.10, gradeCode = "AC-3", installDate = @2009/5/11,
    checkDate = @2011/8/5, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 9, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Solstice pH probe",
    sensorFamily = "Field", measurandName = "Acidity", labCode = "LB-08", unitCode = "pH",
    budgetShare = 0.0240, annualCost = 240000.0, unitCost = 96.40, pointCount = 2489,
    driftPct = 1.20, gradeCode = "AC-2", installDate = @2009/10/6,
    checkDate = @2011/9/2, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 10, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Tundra frequency counter",
    sensorFamily = "Field", measurandName = "Frequency", labCode = "LB-09", unitCode = "Hz",
    budgetShare = 0.0170, annualCost = 170000.0, unitCost = 8.90, pointCount = 19101,
    driftPct = 4.80, gradeCode = "AC-3", installDate = @2010/3/1,
    checkDate = @2011/7/15, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 11, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Rill thermocouple",
    sensorFamily = "Field", measurandName = "Temperature", labCode = "LB-10", unitCode = "K",
    budgetShare = 0.0110, annualCost = 110000.0, unitCost = 21.40, pointCount = 5140,
    driftPct = 2.20, gradeCode = "AC-4", installDate = @2010/6/21,
    checkDate = @2011/9/23, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 12, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Kite manometer",
    sensorFamily = "Field", measurandName = "Pressure", labCode = "LB-11", unitCode = "kPa",
    budgetShare = 0.0060, annualCost = 60000.0, unitCost = 44.80, pointCount = 1339,
    driftPct = 0.00, gradeCode = "AC-5", installDate = @2010/9/13,
    checkDate = @2011/5/20, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 13, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Delta strain gauge",
    sensorFamily = "Field", measurandName = "Strain", labCode = "LB-12", unitCode = "um/m",
    budgetShare = 0.0030, annualCost = 30000.0, unitCost = 6.20, pointCount = 4839,
    driftPct = 3.90, gradeCode = "AC-5", installDate = @2011/1/10,
    checkDate = @2011/8/19, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" },
  { sensorId = 14, programmeCode = "CAL-100", programmeName = "Helios calibration", sensorName = "Reference standard set",
    sensorFamily = "Reference", measurandName = "Reference", labCode = "LB-01", unitCode = "K",
    budgetShare = 0.0010, annualCost = 10000.0, unitCost = 1.00, pointCount = 10000,
    driftPct = 0.10, gradeCode = "AC-0", installDate = @2007/4/2,
    checkDate = @2011/9/30, ownerName = "e.rasmussen",
    standardName = "Reference chain RC-40" }]

-- ================================================= 1. the ATOMIC report model

-- An `Atomic` is a value and its format, nothing more. `val` is
-- `Atomic unit_Fmt`, i.e. "this value, drawn however the medium draws its type".
spendAtom  : Atomic Double
spendAtom  = Atomic (currency_Fmt "USD") 10000000.0

samplesAtom : Atomic Int
samplesAtom = val 862411

uncertaintyAtom : Atomic Double
uncertaintyAtom = Atomic (percentageRound_Fmt 2) 0.0271

-- The eight-number summary block. Every number is a LITERAL here; the same three
-- of them fed from the data are `dataSummary` below, and the only difference is
-- meant to be where the numbers come from -- so the literals have to agree with
-- the relation, and these do:
--
--     programme spend  10,000,000.0  = sum of `annualCost` over all 14 rows
--     sensors          14            = the row count
--     largest share    0.226         = max `budgetShare` (Meridian hygrometer)
--     cost per sample  11.5954       = 10,000,000 / 862,411
--
-- The other four are lab-wide facts with no column in this table at all (samples
-- logged, method uncertainty, runs per week, rejection rate) and are literals for
-- the honest reason that there is nothing here to derive them from.
--
-- AN EARLIER DRAFT HAD THREE OF THESE WRONG -- cost per sample to the fourth
-- decimal, and "largest share" set to the FIRST row's share, not the largest.
-- A hand-typed number in a heading is the least reliable thing in a report;
-- `dataSummary` is the form to prefer wherever the number exists in the data.
staticSummary = valueGrid
  [ ("Programme spend",    atom spendAtom)
  , ("Samples logged",     atom samplesAtom)
  , ("Method uncertainty", atom uncertaintyAtom)
  , ("Cost per sample",    currency "USD" 11.5954)
  , ("Sensors",            wholeNumber 14)
  , ("Largest share",      percent 0.226)
  , ("Runs per week",      rounded 1 42.7)
  , ("Rejection rate",     fmt (percentageRound_Fmt 2) 0.0089) ]

-- The other four layouts for the same pairs. `valueGridN` takes ROWS of pairs,
-- so it makes a two-column-per-column grid; `valueGridR` takes report/report
-- pairs rather than string/report, so the label can be styled; `grid` is the
-- raw form; `hflowLabeled` runs them across instead of down.
twoUp = valueGridN
  [ [ ("Programme spend", currency "USD" 10000000.0)
    , ("Samples logged",  wholeNumber 862411) ]
  , [ ("Cost per sample", currency "USD" 11.5954)
    , ("Uncertainty",     percent 0.0271) ] ]

styledPairs = valueGridR
  [ (style "h5" (text "Programme spend"), currency "USD" 10000000.0)
  , (style "h5" (text "Standard"),        textNoMarkdown "Reference chain RC-40") ]

rawGrid = grid
  [ [ atomShown "Owner",     atomShown "e.rasmussen" ]
  , [ atomShown "Installed", atomShown "2 April 2007" ]
  , [ atomShown "Base unit", atomShown "K" ] ]

-- 14 sensors across 11 measurands and 12 labs -- counted from the table, not
-- guessed. (`Reference standard set` is its own measurand, which is why there are
-- 11 rather than 10; its lab, `LB-01`, it shares with two other sensors.)
acrossTheTop = hflowLabeled
  [ ("Sensors", wholeNumber 14), ("Measurands", wholeNumber 11), ("Labs", wholeNumber 12) ]

-- `labeled` is the one-liner form, and `textVerbatim` is the escape from
-- markdown -- which `text` applies and `textNoMarkdown` does not.
oneLiner   = labeled "Method" "ISO 17025, annual"
verbatimly = textVerbatim "budgetShare * 100 -- not *emphasis*"

-- --------------------------------------------------- dates belong to the writer

-- A `Report` cannot turn a `Date` into a `String` by itself: the format string
-- is a property of the MEDIUM (the JavaFX writer and the Excel writer were
-- parameterised on it), so the report asks for the function and gets it back in
-- a continuation. `formatDate` is the one-value form, `formatDateFn` hands over
-- the function, `formatDateRangeFn` the range form.
checkLine = formatDate @2011/9/30 (s -> labeled "Last check" s)

periodLine = formatDateRange (@2011/1/1, @2011/9/30)
                             (s -> labeled "Period" s)

bothDates = formatDateFn (df ->
  vflow [ labeled "Installed" (df @2007/4/2)
        , labeled "Checked"   (df @2011/9/30) ])

-- A `Presentation` over a PAIR of date columns, which is how a date range
-- becomes one cell of a grid rather than two.
rangePres = dateRange_Pres installDate checkDate

-- ================================================ 2. the RELATIONAL model

measurandTotals : [ measurandName, measurandCost ]
measurandTotals = aggregateByGroup_Agg (sum_Agg (col_Op annualCost)) {measurandName}
                                       measurandCost sensors

sensorsLegend : Legend_Lg (| sensorName, sensorFamily, measurandName, labCode
                           , unitCode, gradeCode, budgetShare, annualCost
                           , unitCost, pointCount, driftPct |)
sensorsLegend =
  withFormats ([ (sensorName,    "Sensor")    ^ 0
               , (sensorFamily,  "Family")    ^ 1
               , (measurandName, "Measurand") ^ 2
               , (labCode,       "Lab")       ^ 3
               , (unitCode,      "Unit")      ^ 4
               , (gradeCode,     "Grade")     ^ 5 ]_Sorted_Lg)
              (round_Fmt 2)
              { budgetShare, annualCost, unitCost, pointCount, driftPct }

sensorsTable =
  tabular_K ([tabLegend_O := sensorsLegend]_Opt)
            (sensors # { sensorName, sensorFamily, measurandName, labCode
                       , unitCode, gradeCode, budgetShare, annualCost
                       , unitCost, pointCount, driftPct })

measurandPie = pieOf "By measurand" measurandName (currency_Pres "USD" measurandCost) measurandTotals

-- ================================================== 3. the bridge: scanRelation

-- The atomic block, fed from the relation. `scanRelation` executes the relation
-- and hands the rows over as a `List {..r}`; from there it is ordinary Ermine --
-- `length`, `foldl`, `!` -- and the report is built with the atomic combinators.
--
-- THIS is the answer to "how do I put a computed total in a heading".
dataSummary =
  scanRelation (sensors # { sensorName, budgetShare, annualCost }) (rows ->
    valueGrid
      [ ("Sensors",        wholeNumber (length rows))
      , ("Total spend",    currency "USD" (sum' (map (r -> r ! annualCost) rows)))
      , ("Largest share",  percent (foldl (max numOrd) 0.0
                                          (map (r -> r ! budgetShare) rows))) ])

-- `scanRelationInOrder` is the same with an explicit `Sort`, so the list arrives
-- ordered and `head` means something. `Has r s` is what checks that the sort's
-- columns are in the relation.
topSensor =
  scanRelationInOrder (invert_Sort (ordering_Sort { budgetShare }))
                      (sensors # { sensorName, budgetShare })
                      (rows -> labeled "Biggest contributor"
                                 (maybeHead "none" (r -> r ! sensorName) rows))

-- `scan` + `runScan` is the continuation-monad form: several relations scanned
-- in one `do` block, each binding its rows, with the report built at the end.
-- `Control.Monad.Cont` is what makes the nesting disappear.
twoScans = runScan (do
  hs <- scan (sensors # { sensorName, budgetShare })
  ss <- scan measurandTotals
  unit (valueGrid [ ("Sensors",    wholeNumber (length hs))
                  , ("Measurands", wholeNumber (length ss)) ]))

-- ==================================== 4. Layout.Report.Relation: the Other bucket

-- The long tail. Three of the fourteen sensors are under one per cent (Kite
-- manometer 0.6 %, Delta strain gauge 0.3 %, the reference set 0.1 %) and a pie
-- chart with fourteen slices is unreadable. `cutoffDrilldownRel` sums every
-- slice below the cutoff into one "Other" row PER PARENT, keeping the total
-- exact, and does it at every level of a drilldown.
--
-- Its signature demands the relation be EXACTLY (group, child, parent, value):
-- `s <- (d, c, p, v)`. That is unusually strict for this library, and it is why
-- the projection below is exact. The value column must be `Nullable Double`
-- because the sums it produces may be null when a parent has no small slices.
slices : [ sliceId, sliceParent, sliceName, sliceWeight ]
slices = relation [
  { sliceId = 1,  sliceParent = 0, sliceName = "Temperature",   sliceWeight = Some 0.195 },
  { sliceId = 2,  sliceParent = 0, sliceName = "Pressure",      sliceWeight = Some 0.158 },
  { sliceId = 3,  sliceParent = 0, sliceName = "Humidity",      sliceWeight = Some 0.226 },
  { sliceId = 4,  sliceParent = 0, sliceName = "Strain",        sliceWeight = Some 0.114 },
  { sliceId = 5,  sliceParent = 0, sliceName = "Flow",          sliceWeight = Some 0.098 },
  { sliceId = 6,  sliceParent = 0, sliceName = "Voltage",       sliceWeight = Some 0.082 },
  { sliceId = 7,  sliceParent = 0, sliceName = "Torque",        sliceWeight = Some 0.046 },
  { sliceId = 8,  sliceParent = 0, sliceName = "Mass",          sliceWeight = Some 0.039 },
  { sliceId = 9,  sliceParent = 0, sliceName = "Acidity",       sliceWeight = Some 0.024 },
  { sliceId = 10, sliceParent = 0, sliceName = "Frequency",     sliceWeight = Some 0.017 },
  { sliceId = 11, sliceParent = 0, sliceName = "Reference",     sliceWeight = Some 0.001 } ]

-- Everything under five per cent of its parent's total is swept into "Other".
-- The exception is deliberate and worth knowing: if exactly ONE slice falls
-- below the cutoff, it keeps its own name and id rather than becoming a bucket
-- of one -- `others` checks `cutoffCount == 1`.
withOther = cutoffDrilldownRel_RR sliceWeight sliceParent sliceId 0.05 sliceName slices

bucketedPie = pieOf "By measurand, small slices bucketed"
                    sliceName (percent_Pres sliceWeight) withOther

-- ============================================ 5. the layout combinators

-- `Tree` from the `Tree` module, drawn by `tree`: a report per node, nested.
-- Nothing else in `core/examples` draws one.
sensorTree =
  tree (text "Helios calibration")
       (node_T (text "Field")
               [ node_T (text "Temperature") []
               , node_T (text "Pressure")    [] ])

tabs = tabbed [ ("Sensors",    sensorsTable)
              , ("Measurands", tabular Nothing measurandTotals)
              , ("Summary",    staticSummary) ]

sideTabs = sideTabbed [ ("By measurand", measurandPie)
                      , ("Bucketed",     bucketedPie) ]

folded = collapsible False "Full sensor register" sensorsTable

detail = summaryDetail (h3 "Helios calibration") (text "A traceable calibration programme.")

ribbon = sectionRibbon (h3 "Sensors") (textNoMarkdown "as at 30 September 2011")

sides = floatSides (text "Helios calibration") (text "annual programme")

-- ==================================================================== the page

factsheet = vflow [
  h2 "Helios calibration -- factsheet",
  sides,
  hspan [ box (pad2 staticSummary), box (pad2 dataSummary) ],
  acrossTheTop,
  vstrut,
  bothDates,
  checkLine,
  periodLine,
  topSensor,
  twoScans,
  vstrut,
  detail,
  ribbon,
  tabs,
  sideTabs,
  folded,
  vstrut,
  hugL (h3 "The long tail, bucketed"),
  tabular Nothing withOther,
  hugR (textNoMarkdown "small slices summed into Other, total preserved"),
  vstrut,
  sensorTree,
  twoUp,
  styledPairs,
  rawGrid,
  oneLiner,
  verbatimly
]
