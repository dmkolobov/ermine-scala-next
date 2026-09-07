module Present.FulcrumPanel where

{- TWO FULCRUM REPORTS over a THIRTY-COLUMN turbine table: the same quarterly
   grid built once by `Layout.Report.Fulcrum.Dynamic` (the column set decided at
   scan time, from the data) and once by `Layout.Report.Fulcrum.Legendary` (the
   column set decided at compile time, with a legend attached to each column).

   Fact: turbines (30 fields: turbineRowId, asOfDate, siteCode,
         siteName, arrayName, mountingType, operatorName, assetTag,
         turbineId, turbineName, turbineClass, terrainType, foundationType,
         countryCode, gridCode, substationCode, ratedKw, windSpeedMs, airDensity,
         energyMwh, expectedMwh, surplusMwh, curtailedMwh, availPct,
         referenceAvailPct, deltaAvailPct, serviceYears, capacityPct,
         serviceGrade, periodLabel)

   WHY THIS FILE EXISTS. A "fulcrum" is Ermine's word for the thing a spreadsheet
   calls a pivot: a relation in LONG form (one row per key per period) redrawn in
   WIDE form (one column per period). `core/examples` had exactly one pivot
   example, `PivotTest.e`, which pivots three columns and never mentions a
   legend; `Layout.Report.Fulcrum.Dynamic` and `Fulcrum.Legendary` had none at
   all. They are the two ends of a real design choice:

     Dynamic     `Row k` + `{..k} -> PivotColumn v`. The columns are whatever
                 distinct values the key column turns out to have; the report
                 scans the key column first and then builds the schema. New
                 quarter in the data, new column in the grid, no code change.

     Legendary   a chain of `single_Brace`/`snoc_Brace`, one link per column,
                 each carrying a `Field`, a `Legend`, an `Op` and the key VALUE
                 that column selects. The columns are fixed in the source, and
                 in exchange each one gets its own format, label and group.

   THE ROW-SOLVER INTEREST. `Legendary.snoc_Brace` carries an `RUnion2` -- a
   three-variable row-union constraint -- PER LINK, and `single_Brace`/`(<>)`
   carry more. The `core/examples/Ai/README.md` cliff says that bundling
   `RUnion3` and `RUnion2` into one signature hung the compiler. Chained FOUR
   deep here, at the row-solver defaults adopted at `fe024a7`, it costs nothing
   measurable: see `tracker/loopmodel/E4-EXAMPLES.md` section 4. That is the
   headline finding of this module.

   SHAPES EXERCISED
     * `pivotTabular'` with a `DynamicFulcrum` over a 30-column fact table:
       `r <- (k, v, i)` with **twenty-eight** columns in `i`.
     * `fulcrumOf` -- the generic `DynamicFulcrum` constructor from `Helpers.e`.
     * `Layout.Report.Fulcrum.Dynamic.pivotColumn`'s rank-2 third argument
       (`forall f. Field f a -> Presentation f a`), applied at three different
       formats chosen PER KEY VALUE.
     * `Legendary`'s `single_Brace` / `snoc_Brace` / `fulcrumGroup` / `(<>)`
       chained four deep, then taken apart by pattern match and fed to
       `Relation.Pivot.pivot`.
     * `MythicalFulcrum` -- the existential wrapper -- and `(><)`, which joins
       two fulcrums whose column rows are not statically known.
     * A legend pinned by `pinned` and grouped by `groupedAs` across the
       identifier columns AND the pivoted columns at once.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/FulcrumPanel.e
     >> quarterlyDynamic
     >> quarterlyLegendary
     >> longForm

   CAUTION -- a live runtime bug, not a typing one. Forcing a pivoted relation
   panics: `Relation.Pivot.pivot` goes through `Native.Record.scalaRecord#`,
   which since Scala 2.13 receives a lazy `MapView` from `record#` and does not
   match its `Map` case. See `tracker/loopmodel/E1-EXAMPLES.md` section 7.2 --
   the diagnosis and the one-line fix are recorded there. Everything in this
   module TYPE-checks; `pivotedWide` is the binding that would panic if forced.

   `bothHalves` shows the SAME bug at its OTHER site. Evaluating it prints the
   fulcrum and, inside it, `<error: Panic: unexpected runtime value in
   Record.header# - MapView(<not computed>)>` -- `Native.Record.header#`
   (`Lib.scala:1016`) has the identical `case Prim(r : Map[String,Runtime])`
   pattern as `scalaRecord#`, and `emptyLF`'s `nilFulcrum (header k)` is what
   reaches it. E1 section 7.2 predicted this site and noted that nothing had
   forced it; this module does. Same one-character fix, `.toMap`.

   There is no `render` either; see gate G4.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Magnitude
import Layout.Report.Fulcrum.Dynamic as DF
import Layout.Report.Fulcrum.Legendary as LF
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Relation.Op as Op
import Relation.Pivot as Piv
import Relation.Sort as Sort
import Syntax.Relation
import Present.Helpers

field turbineRowId : Int
field asOfDate : Date
field siteCode, siteName, arrayName, mountingType : String
field operatorName, assetTag, turbineId, turbineName : String
field turbineClass, terrainType, foundationType, countryCode : String
field gridCode, substationCode, serviceGrade, periodLabel : String
field ratedKw, windSpeedMs, airDensity, energyMwh, expectedMwh : Double
field surplusMwh, curtailedMwh, availPct, referenceAvailPct : Double
field deltaAvailPct, serviceYears, capacityPct : Double

field q1Value, q2Value, q3Value, q4Value : Double
field q1Avail, q2Avail : Double

-- ------------------------------------------------------------- the fact table

-- Thirty columns; three turbines observed at four quarter ends.
turbines : [ turbineRowId, asOfDate, siteCode, siteName, arrayName
           , mountingType, operatorName, assetTag, turbineId
           , turbineName, turbineClass, terrainType, foundationType, countryCode
           , gridCode, substationCode, ratedKw, windSpeedMs, airDensity
           , energyMwh, expectedMwh, surplusMwh, curtailedMwh, availPct
           , referenceAvailPct, deltaAvailPct, serviceYears, capacityPct
           , serviceGrade, periodLabel ]
turbines = relation [
  { turbineRowId = 1, asOfDate = @2011/3/31, siteCode = "WF-100", siteName = "Glen Aber Ridge",
    arrayName = "North string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-88214",
    turbineId = "WT-0041", turbineName = "Northwind A12", turbineClass = "Onshore", terrainType = "Ridge",
    foundationType = "Rock anchor", countryCode = "GB", gridCode = "33KV", substationCode = "SUB-A1",
    ratedKw = 3600.0, windSpeedMs = 8.40, airDensity = 1.25, energyMwh = 2444.00,
    expectedMwh = 2248.48, surplusMwh = 195.52, curtailedMwh = 0.00, availPct = 96.40,
    referenceAvailPct = 95.00, deltaAvailPct = 1.40, serviceYears = 3.00,
    capacityPct = 31.00, serviceGrade = "A1", periodLabel = "Q1" },
  { turbineRowId = 2, asOfDate = @2011/6/30, siteCode = "WF-100", siteName = "Glen Aber Ridge",
    arrayName = "North string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-88214",
    turbineId = "WT-0041", turbineName = "Northwind A12", turbineClass = "Onshore", terrainType = "Ridge",
    foundationType = "Rock anchor", countryCode = "GB", gridCode = "33KV", substationCode = "SUB-A1",
    ratedKw = 3600.0, windSpeedMs = 6.90, airDensity = 1.22, energyMwh = 1980.00,
    expectedMwh = 1821.60, surplusMwh = 158.40, curtailedMwh = 0.00, availPct = 97.20,
    referenceAvailPct = 95.00, deltaAvailPct = 2.20, serviceYears = 3.25,
    capacityPct = 25.10, serviceGrade = "A1", periodLabel = "Q2" },
  { turbineRowId = 3, asOfDate = @2011/9/30, siteCode = "WF-100", siteName = "Glen Aber Ridge",
    arrayName = "North string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-88214",
    turbineId = "WT-0041", turbineName = "Northwind A12", turbineClass = "Onshore", terrainType = "Ridge",
    foundationType = "Rock anchor", countryCode = "GB", gridCode = "33KV", substationCode = "SUB-A1",
    ratedKw = 3600.0, windSpeedMs = 7.10, airDensity = 1.21, energyMwh = 2065.00,
    expectedMwh = 1899.80, surplusMwh = 165.20, curtailedMwh = 0.00, availPct = 95.10,
    referenceAvailPct = 95.00, deltaAvailPct = 0.10, serviceYears = 3.50,
    capacityPct = 26.20, serviceGrade = "A1", periodLabel = "Q3" },
  { turbineRowId = 4, asOfDate = @2011/12/31, siteCode = "WF-100", siteName = "Glen Aber Ridge",
    arrayName = "North string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-88214",
    turbineId = "WT-0041", turbineName = "Northwind A12", turbineClass = "Onshore", terrainType = "Ridge",
    foundationType = "Rock anchor", countryCode = "GB", gridCode = "33KV", substationCode = "SUB-A1",
    ratedKw = 3600.0, windSpeedMs = 9.30, airDensity = 1.26, energyMwh = 2688.00,
    expectedMwh = 2472.96, surplusMwh = 215.04, curtailedMwh = 0.00, availPct = 96.80,
    referenceAvailPct = 95.00, deltaAvailPct = 1.80, serviceYears = 3.75,
    capacityPct = 34.10, serviceGrade = "A1", periodLabel = "Q4" },
  { turbineRowId = 5, asOfDate = @2011/3/31, siteCode = "WF-210", siteName = "Cloghan Plateau",
    arrayName = "West string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-91307",
    turbineId = "WT-0177", turbineName = "Kestrel B07", turbineClass = "Onshore", terrainType = "Plateau",
    foundationType = "Gravity pad", countryCode = "IE", gridCode = "33KV", substationCode = "SUB-B2",
    ratedKw = 2500.0, windSpeedMs = 7.80, airDensity = 1.24, energyMwh = 1610.00,
    expectedMwh = 1481.20, surplusMwh = 128.80, curtailedMwh = 12.40, availPct = 93.60,
    referenceAvailPct = 94.00, deltaAvailPct = -0.40, serviceYears = 5.00,
    capacityPct = 29.40, serviceGrade = "B2", periodLabel = "Q1" },
  { turbineRowId = 6, asOfDate = @2011/6/30, siteCode = "WF-210", siteName = "Cloghan Plateau",
    arrayName = "West string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-91307",
    turbineId = "WT-0177", turbineName = "Kestrel B07", turbineClass = "Onshore", terrainType = "Plateau",
    foundationType = "Gravity pad", countryCode = "IE", gridCode = "33KV", substationCode = "SUB-B2",
    ratedKw = 2500.0, windSpeedMs = 6.40, airDensity = 1.21, energyMwh = 1284.00,
    expectedMwh = 1181.28, surplusMwh = 102.72, curtailedMwh = 8.10, availPct = 94.80,
    referenceAvailPct = 94.00, deltaAvailPct = 0.80, serviceYears = 5.25,
    capacityPct = 23.50, serviceGrade = "B2", periodLabel = "Q2" },
  { turbineRowId = 7, asOfDate = @2011/9/30, siteCode = "WF-210", siteName = "Cloghan Plateau",
    arrayName = "West string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-91307",
    turbineId = "WT-0177", turbineName = "Kestrel B07", turbineClass = "Onshore", terrainType = "Plateau",
    foundationType = "Gravity pad", countryCode = "IE", gridCode = "33KV", substationCode = "SUB-B2",
    ratedKw = 2500.0, windSpeedMs = 6.70, airDensity = 1.20, energyMwh = 1355.00,
    expectedMwh = 1246.60, surplusMwh = 108.40, curtailedMwh = 5.60, availPct = 95.30,
    referenceAvailPct = 94.00, deltaAvailPct = 1.30, serviceYears = 5.50,
    capacityPct = 24.80, serviceGrade = "B2", periodLabel = "Q3" },
  { turbineRowId = 8, asOfDate = @2011/12/31, siteCode = "WF-210", siteName = "Cloghan Plateau",
    arrayName = "West string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-91307",
    turbineId = "WT-0177", turbineName = "Kestrel B07", turbineClass = "Onshore", terrainType = "Plateau",
    foundationType = "Gravity pad", countryCode = "IE", gridCode = "33KV", substationCode = "SUB-B2",
    ratedKw = 2500.0, windSpeedMs = 8.50, airDensity = 1.25, energyMwh = 1742.00,
    expectedMwh = 1602.64, surplusMwh = 139.36, curtailedMwh = 21.30, availPct = 92.70,
    referenceAvailPct = 94.00, deltaAvailPct = -1.30, serviceYears = 5.75,
    capacityPct = 31.80, serviceGrade = "B2", periodLabel = "Q4" },
  { turbineRowId = 9, asOfDate = @2011/3/31, siteCode = "WF-330", siteName = "Noordbank Shoal",
    arrayName = "Sea string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-77452",
    turbineId = "WT-2208", turbineName = "Meridian C03", turbineClass = "Offshore", terrainType = "Shoal",
    foundationType = "Monopile", countryCode = "NL", gridCode = "66KV", substationCode = "SUB-C3",
    ratedKw = 6000.0, windSpeedMs = 9.60, airDensity = 1.27, energyMwh = 5412.00,
    expectedMwh = 4979.04, surplusMwh = 432.96, curtailedMwh = 96.50, availPct = 97.10,
    referenceAvailPct = 96.50, deltaAvailPct = 0.60, serviceYears = 2.00,
    capacityPct = 41.20, serviceGrade = "A2", periodLabel = "Q1" },
  { turbineRowId = 10, asOfDate = @2011/6/30, siteCode = "WF-330", siteName = "Noordbank Shoal",
    arrayName = "Sea string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-77452",
    turbineId = "WT-2208", turbineName = "Meridian C03", turbineClass = "Offshore", terrainType = "Shoal",
    foundationType = "Monopile", countryCode = "NL", gridCode = "66KV", substationCode = "SUB-C3",
    ratedKw = 6000.0, windSpeedMs = 8.20, airDensity = 1.24, energyMwh = 4480.00,
    expectedMwh = 4121.60, surplusMwh = 358.40, curtailedMwh = 74.20, availPct = 96.90,
    referenceAvailPct = 96.50, deltaAvailPct = 0.40, serviceYears = 2.25,
    capacityPct = 34.10, serviceGrade = "A2", periodLabel = "Q2" },
  { turbineRowId = 11, asOfDate = @2011/9/30, siteCode = "WF-330", siteName = "Noordbank Shoal",
    arrayName = "Sea string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-77452",
    turbineId = "WT-2208", turbineName = "Meridian C03", turbineClass = "Offshore", terrainType = "Shoal",
    foundationType = "Monopile", countryCode = "NL", gridCode = "66KV", substationCode = "SUB-C3",
    ratedKw = 6000.0, windSpeedMs = 8.80, airDensity = 1.23, energyMwh = 4826.00,
    expectedMwh = 4439.92, surplusMwh = 386.08, curtailedMwh = 61.80, availPct = 95.40,
    referenceAvailPct = 96.50, deltaAvailPct = -1.10, serviceYears = 2.50,
    capacityPct = 36.70, serviceGrade = "A2", periodLabel = "Q3" },
  { turbineRowId = 12, asOfDate = @2011/12/31, siteCode = "WF-330", siteName = "Noordbank Shoal",
    arrayName = "Sea string", mountingType = "Fixed base", operatorName = "Northgate O&M", assetTag = "AST-77452",
    turbineId = "WT-2208", turbineName = "Meridian C03", turbineClass = "Offshore", terrainType = "Shoal",
    foundationType = "Monopile", countryCode = "NL", gridCode = "66KV", substationCode = "SUB-C3",
    ratedKw = 6000.0, windSpeedMs = 10.40, airDensity = 1.28, energyMwh = 6014.00,
    expectedMwh = 5532.88, surplusMwh = 481.12, curtailedMwh = 118.40, availPct = 97.60,
    referenceAvailPct = 96.50, deltaAvailPct = 1.10, serviceYears = 2.75,
    capacityPct = 45.80, serviceGrade = "A2", periodLabel = "Q4" }]

-- The long form the fulcrum reads: one row per turbine per quarter.
longForm : [ turbineName, terrainType, turbineClass, serviceGrade, periodLabel
           , energyMwh ]
longForm = turbines # { turbineName, terrainType, turbineClass, serviceGrade
                      , periodLabel, energyMwh }

-- ======================================================= 1. the DYNAMIC fulcrum

-- One `PivotColumn` per distinct value of `periodLabel`. The third argument of
-- `pivotColumn` is RANK-2 -- `forall f. Field f a -> Presentation f a` -- because
-- the field it will be applied to does not exist until the column is minted, and
-- its name comes from the KEY VALUE at scan time. `round_Pres 0` is such a
-- function; so is `basic_Pres`.
--
-- Notice that the format is chosen per key: the fourth quarter is the one people
-- read, so it keeps two decimals; the rest are rounded to whole megawatt-hours.
quarterColumn k =
  if (k ! periodLabel == "Q4")
     (pivotColumn_DF (col_Op energyMwh) (k ! periodLabel) (round_Pres 2))
     (pivotColumn_DF (col_Op energyMwh) (k ! periodLabel) (round_Pres 0))

-- `fulcrumOf` (from `Helpers.e`) is `DynamicFulcrum` with the key ordering taken
-- from the key row, which is the sensible default; the explicit form below shows
-- the other half of the choice, an `Ord` on the key RECORD rather than a `Sort`.
quarterFulcrum : DynamicFulcrum_DF (| periodLabel |) (| energyMwh |)
quarterFulcrum = fulcrumOf {periodLabel} quarterColumn

-- The identifier legend: four columns, labelled, with an initial sort, and the
-- three that matter grouped under one heading.
identifierLegend : Legend_Lg (| turbineName, terrainType, turbineClass, serviceGrade |)
identifierLegend =
  groupedAs "Turbine"
    ([ (turbineName,  "Turbine")     ^ 0
     , (terrainType,  "Terrain")     ^ 1
     , (turbineClass, "Turbine class") ^ 2
     , (serviceGrade, "Grade")       ^! 3 ]_Sorted_Lg)

-- THE REPORT. `r <- (k, v, i)`: key `periodLabel`, value `energyMwh`, and the
-- four identifier columns.
quarterlyDynamic = pivotTabular' quarterFulcrum (Just identifierLegend) longForm

-- The SAME fulcrum against the WHOLE thirty-column fact table -- twenty-eight
-- columns in the identifier part. Nothing changes except how much the solver
-- has to carry.
quarterlyWide = pivotTabular' quarterFulcrum Nothing turbines

-- ==================================================== 2. the LEGENDARY fulcrum

-- One link per column, each carrying (field, legend, op, key value). The chain
-- is `single_Brace` then three `snoc_Brace`s; each `snoc` adds an `RUnion2` over
-- the value row. `Legendary` defines its own `single_Brace`/`snoc_Brace`, which
-- collide with `Relation.Row`'s `{...}` syntax, so they are called as ordinary
-- functions here -- which is also clearer about what the chain is.
q1 = single_Brace_LF ( q1Value
                     , legend_Lg (round_Pres 0 q1Value) "Q1"
                     , col_Op energyMwh
                     , {periodLabel = "Q1"} )

q12 = snoc_Brace_LF q1 ( q2Value
                       , legend_Lg (round_Pres 0 q2Value) "Q2"
                       , col_Op energyMwh
                       , {periodLabel = "Q2"} )

q123 = snoc_Brace_LF q12 ( q3Value
                         , legend_Lg (round_Pres 0 q3Value) "Q3"
                         , col_Op energyMwh
                         , {periodLabel = "Q3"} )

-- The fourth quarter keeps two decimals, and the whole set gets a spanning heading.
-- `fulcrumGroup` is `mapLegend legendGroup`: it touches the legend and leaves
-- the pivot alone, which is the point of keeping the two in one structure.
q1234 = fulcrumGroup_LF "Energy output by quarter"
          (snoc_Brace_LF q123 ( q4Value
                              , legend_Lg (round_Pres 2 q4Value) "Q4"
                              , col_Op energyMwh
                              , {periodLabel = "Q4"} ))

-- Taking it apart: `LF` holds the `Fulcrum` and the `Legend` side by side, so
-- the report is `pivot` on one and `tabular` on the other, and the two cannot
-- drift apart because they were built together.
--
-- CAUTION: forcing `pivotedWide` panics -- see the module header.
pivotedWide = case q1234 of
  LF_LF ful _ -> pivot_Piv ful (asMem longForm)

quarterlyLegendary = case q1234 of
  LF_LF ful lg ->
    tabular_K ([tabLegend_O := identifierLegend ++_Lg lg]_Opt)
              (pivot_Piv ful (asMem longForm))

-- ------------------------------------------- the existential form

-- `MythicalFulcrum` hides the column row, so two independently-built fulcrums
-- can be joined by `(><)` even though neither's column set is written down.
-- This is what a report builder does when the column set comes from a
-- configuration file rather than from the source.
availHalf =
  MF_LF (snoc_Brace_LF (single_Brace_LF ( q1Avail
                                        , legend_Lg (percent_Pres q1Avail) "Q1 av"
                                        , col_Op availPct
                                        , {periodLabel = "Q1"} ))
                       ( q2Avail
                       , legend_Lg (percent_Pres q2Avail) "Q2 av"
                       , col_Op availPct
                       , {periodLabel = "Q2"} ))

valueHalf = MF_LF q1234

bothHalves = valueHalf ><_LF availHalf

-- ==================================================== the page, and the contrast

fulcrumPanel = vflow [
  h2 "Quarterly energy output -- two ways to build the same grid",
  h3 "Dynamic: the columns are whatever quarters the data has",
  quarterlyDynamic,
  h3 "Legendary: the columns are named, formatted and grouped in the source",
  quarterlyLegendary,
  h3 "The long form the two of them read",
  tabular Nothing longForm,
  vstrut,
  textNoMarkdown ("A new quarter appears in the Dynamic grid without a code " ++_String
                  "change, and does not appear in the Legendary one at all.")
]
