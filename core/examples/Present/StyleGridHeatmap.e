module Present.StyleGridHeatmap where

{- A RISK HEAT MAP: `Layout.Report.styleBox` -- the one report combinator that
   lays cells out by POSITION rather than by row -- plus `Layout.Report.StyleGrid`,
   `Layout.Color`, `Layout.Magnitude` in all three of its units, and a treemap.

   Fact: risks (16 fields: riskId, riskTitle, ownerName, categoryName,
         businessUnit, probScore, impactScore, impactUsd, mitigationState,
         reviewDate, residualScore, xPos, yPos, statusName, probBand,
         impactBand)

   WHY THIS FILE EXISTS. `styleBox` is the odd one out in `Layout.Report`: every
   other combinator draws a relation as a LIST of rows, and this one draws it as
   a two-dimensional GRID whose cell coordinates are columns of the relation.
   It had no example. Neither had `Layout.Report.StyleGrid`, `Layout.Color`
   beyond a chart palette, `Layout.Magnitude`'s `Area` / `Volume` / `ratioA`, or
   `treemapChart`.

   HOW `styleBox` IS TYPED, and it is worth reading twice:

       styleBox : (r <- (px, py, xv, yv, av, other), l <- (xv, yv, av, other))
               => (Legend l, Field xv a, Field yv b, Field av c)
               -> Bool -> List String -> List String
               -> List# (Pair# Double Double) -> List# (Pair# Double Double)
               -> Field px Int -> Field py Int -> rel r -> Report f z

   SIX parts in the fact row and FOUR in the legend, and the two partitions
   overlap in three of them. `px`/`py` are the CELL COORDINATES -- integers, and
   the only columns the legend does NOT carry, because they are the layout and
   not the content. `xv`/`yv` are the values that gave rise to those
   coordinates, `av` is what the cell shows, and `other` is everything else,
   which appears in the tooltip. Getting this wrong is the most likely mistake a
   reader will make, and `shouldfail/box01_position_in_legend.e` records exactly
   what the compiler says when they do.

   THE BINS. `xBins` and `yBins` are `(lo, hi)` pairs, one per column and row of
   the grid; they are `List#` and `Pair#` -- the NATIVE types -- because they go
   straight to the writer, which is a reminder that `styleBox` is a thin wrapper
   over a writer primitive and not a piece of the relational language.

   SHAPES EXERCISED
     * `styleBox` with a 5 x 5 bin grid over a 16-column fact table.
     * `Layout.Report.StyleGrid`: `StyleGrid a = List (Maybe String, List (Maybe
       String, a))` -- a grid of optional CSS classes -- and `mapStyleGrid`.
     * `Layout.Color`: `rgb`, `rgba`, `rgbRead` (parsing "#c62828"),
       `standardColors` as a `Map`, and the named constants.
     * `Layout.Magnitude` in all three units -- `cells`, `pixels`,
       `dimensionless` -- plus `Area` through `cellsA` / `pixelsA` / `ratioA`,
       and `Volume`.
     * `bandedBy` giving each cell its colour from its own residual score, so
       the heat is a FORMAT and not a writer setting.
     * `treemapChart`: parent/child ids, a label, an INTENSITY measure and a
       SIZE measure -- and the two measures must be DIFFERENT columns, because
       `r <- (labels, ivalue, svalue, r1, r2, o)` is a partition and a partition
       is disjoint. That is a real constraint a reader will hit.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/StyleGridHeatmap.e
     >> heatMap
     >> risks
     >> impactTree

   There is no `render`; evaluate the report and the relations. See
   `tracker/loopmodel/E4-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Color
import Layout.Magnitude
import Layout.Report.StyleGrid as SG
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Map as M
import Relation.Op as Op
import Relation.Aggregate as Agg
import Relation.Sort as Sort
import Syntax.Relation
import Syntax.List
import Present.Helpers

field riskId, xPos, yPos : Int
field riskTitle, ownerName, categoryName, businessUnit : String
field mitigationState, statusName, probBand, impactBand : String
field reviewDate : Date
field probScore, impactScore, impactUsd, residualScore : Double

field nodeKey, parentKey : Int
field nodeName : String
field nodeImpact, nodeIntensity : Double

-- ------------------------------------------------------------- the fact table

-- Sixteen columns, sixteen risks on a 5 x 5 probability/impact grid. `xPos` and
-- `yPos` are the cell coordinates, zero-based; `probScore` and `impactScore`
-- are the values behind them.
risks : [ riskId, riskTitle, ownerName, categoryName, businessUnit, probScore
        , impactScore, impactUsd, mitigationState, reviewDate, residualScore
        , xPos, yPos, statusName, probBand, impactBand ]
risks = relation [
  { riskId = 1, riskTitle = "Supplier concentration", ownerName = "m.iverson", categoryName = "Operational",
    businessUnit = "Manufacturing", probScore = 4.0, impactScore = 5.0, impactUsd = 1250000.0,
    mitigationState = "Mitigating", reviewDate = @2011/10/14, residualScore = 3.6, xPos = 3,
    yPos = 4, statusName = "Open", probBand = "P4", impactBand = "I5" },
  { riskId = 2, riskTitle = "FX volatility, EUR sales", ownerName = "l.dubois", categoryName = "Financial",
    businessUnit = "Corporate", probScore = 3.0, impactScore = 4.0, impactUsd = 940000.0,
    mitigationState = "Hedged", reviewDate = @2011/11/2, residualScore = 2.4, xPos = 2,
    yPos = 3, statusName = "Open", probBand = "P3", impactBand = "I4" },
  { riskId = 3, riskTitle = "Data centre single point", ownerName = "a.silva", categoryName = "Technology",
    businessUnit = "Platform", probScore = 2.0, impactScore = 5.0, impactUsd = 2100000.0,
    mitigationState = "Planned", reviewDate = @2011/9/29, residualScore = 3.1, xPos = 1,
    yPos = 4, statusName = "Open", probBand = "P2", impactBand = "I5" },
  { riskId = 4, riskTitle = "Key person dependency", ownerName = "p.nakamura", categoryName = "People",
    businessUnit = "Commercial", probScore = 4.0, impactScore = 3.0, impactUsd = 480000.0,
    mitigationState = "Accepted", reviewDate = @2011/12/1, residualScore = 3.0, xPos = 3,
    yPos = 2, statusName = "Open", probBand = "P4", impactBand = "I3" },
  { riskId = 5, riskTitle = "Regulatory change, EU", ownerName = "l.dubois", categoryName = "Compliance",
    businessUnit = "Corporate", probScore = 3.0, impactScore = 5.0, impactUsd = 1700000.0,
    mitigationState = "Monitoring", reviewDate = @2011/10/7, residualScore = 3.9, xPos = 2,
    yPos = 4, statusName = "Open", probBand = "P3", impactBand = "I5" },
  { riskId = 6, riskTitle = "Bad debt, top client", ownerName = "l.dubois", categoryName = "Financial",
    businessUnit = "Commercial", probScore = 2.0, impactScore = 4.0, impactUsd = 860000.0,
    mitigationState = "Insured", reviewDate = @2011/11/18, residualScore = 1.8, xPos = 1,
    yPos = 3, statusName = "Closed", probBand = "P2", impactBand = "I4" },
  { riskId = 7, riskTitle = "Cyber intrusion", ownerName = "a.silva", categoryName = "Technology",
    businessUnit = "Platform", probScore = 3.0, impactScore = 5.0, impactUsd = 3400000.0,
    mitigationState = "Mitigating", reviewDate = @2011/9/9, residualScore = 3.4, xPos = 2,
    yPos = 4, statusName = "Open", probBand = "P3", impactBand = "I5" },
  { riskId = 8, riskTitle = "Warehouse fire", ownerName = "m.iverson", categoryName = "Operational",
    businessUnit = "Manufacturing", probScore = 1.0, impactScore = 5.0, impactUsd = 1900000.0,
    mitigationState = "Insured", reviewDate = @2011/12/20, residualScore = 1.5, xPos = 0,
    yPos = 4, statusName = "Closed", probBand = "P1", impactBand = "I5" },
  { riskId = 9, riskTitle = "Talent attrition", ownerName = "p.nakamura", categoryName = "People",
    businessUnit = "Technology", probScore = 5.0, impactScore = 2.0, impactUsd = 320000.0,
    mitigationState = "Mitigating", reviewDate = @2011/10/28, residualScore = 3.2, xPos = 4,
    yPos = 1, statusName = "Open", probBand = "P5", impactBand = "I2" },
  { riskId = 10, riskTitle = "Licence renegotiation", ownerName = "a.silva", categoryName = "Commercial",
    businessUnit = "Platform", probScore = 4.0, impactScore = 2.0, impactUsd = 260000.0,
    mitigationState = "Planned", reviewDate = @2011/11/11, residualScore = 2.6, xPos = 3,
    yPos = 1, statusName = "Open", probBand = "P4", impactBand = "I2" },
  { riskId = 11, riskTitle = "Transfer pricing audit", ownerName = "l.dubois", categoryName = "Compliance",
    businessUnit = "Corporate", probScore = 2.0, impactScore = 3.0, impactUsd = 540000.0,
    mitigationState = "Monitoring", reviewDate = @2011/12/8, residualScore = 1.9, xPos = 1,
    yPos = 2, statusName = "Open", probBand = "P2", impactBand = "I3" },
  { riskId = 12, riskTitle = "Freight cost inflation", ownerName = "m.iverson", categoryName = "Operational",
    businessUnit = "Manufacturing", probScore = 5.0, impactScore = 3.0, impactUsd = 710000.0,
    mitigationState = "Accepted", reviewDate = @2011/10/3, residualScore = 3.8, xPos = 4,
    yPos = 2, statusName = "Open", probBand = "P5", impactBand = "I3" },
  { riskId = 13, riskTitle = "Product recall", ownerName = "m.iverson", categoryName = "Operational",
    businessUnit = "Manufacturing", probScore = 1.0, impactScore = 4.0, impactUsd = 1450000.0,
    mitigationState = "Planned", reviewDate = @2011/11/25, residualScore = 1.4, xPos = 0,
    yPos = 3, statusName = "Closed", probBand = "P1", impactBand = "I4" },
  { riskId = 14, riskTitle = "Channel conflict", ownerName = "p.nakamura", categoryName = "Commercial",
    businessUnit = "Commercial", probScore = 3.0, impactScore = 2.0, impactUsd = 190000.0,
    mitigationState = "Accepted", reviewDate = @2011/9/16, residualScore = 2.2, xPos = 2,
    yPos = 1, statusName = "Closed", probBand = "P3", impactBand = "I2" },
  { riskId = 15, riskTitle = "Cloud vendor lock-in", ownerName = "a.silva", categoryName = "Technology",
    businessUnit = "Platform", probScore = 4.0, impactScore = 4.0, impactUsd = 980000.0,
    mitigationState = "Monitoring", reviewDate = @2011/12/15, residualScore = 3.5, xPos = 3,
    yPos = 3, statusName = "Open", probBand = "P4", impactBand = "I4" },
  { riskId = 16, riskTitle = "Pension deficit", ownerName = "l.dubois", categoryName = "Financial",
    businessUnit = "Corporate", probScore = 2.0, impactScore = 2.0, impactUsd = 150000.0,
    mitigationState = "Accepted", reviewDate = @2011/10/21, residualScore = 1.2, xPos = 1,
    yPos = 1, statusName = "Closed", probBand = "P2", impactBand = "I2" }]

-- ================================================================ the palette

-- `Layout.Color` is `java.awt.Color`: named constants, `rgb` / `rgba` with the
-- arguments clamped to [0, 255], a hex parser, and a `Map String Color` of the
-- thirteen named ones.
coolGrey  = rgb 108 117 125
warmAmber = rgb 196 132  12
hotRed    = rgb 176  42  30
translucent = rgba 176 42 30 96

-- `rgbRead` parses "#c62828" or "c62828" or the three-digit "c28" form, and
-- answers `Nothing` for anything else -- so a colour from a configuration file
-- is a `Maybe Color` and has to be handled.
brandColor = orElse hotRed (rgbRead "#c62828")

-- The named palette, as a `Map`. `lookupOr` gives the fallback.
namedRed = lookupOr_M red "red" standardColors

-- ================================================================= the heat

-- Each cell is coloured by its own residual score, in three bands. The colour
-- is a `Format`, i.e. part of the `Presentation`, i.e. attached to the COLUMN --
-- so the same rule serves the heat map, the table and the tooltip.
heatPres = bandedBy 2.0 3.3 coolGrey warmAmber hotRed (round_Fmt 1) residualScore

-- The legend `styleBox` wants covers the value columns AND everything carried
-- into the tooltip -- but NOT the two position columns.
boxLegend : Legend_Lg (| probScore, impactScore, residualScore, riskTitle
                        , ownerName, categoryName, impactUsd, statusName |)
boxLegend =
  ( labelled probScore   "Probability"
  . labelled impactScore "Impact"
  . labelled heatPres    "Residual"
  . labelled riskTitle   "Risk"
  . labelled ownerName   "Owner"
  . labelled categoryName "Category"
  . labelled (currency_Pres "USD" impactUsd) "Impact value"
  . labelled statusName  "Status" ) empty_Lg

-- Five bins each way, as (lo, hi) pairs in NATIVE list/pair form -- these go
-- straight to the writer.
bands = toList# [ toPair# (0.5, 1.5), toPair# (1.5, 2.5), toPair# (2.5, 3.5)
                , toPair# (3.5, 4.5), toPair# (4.5, 5.5) ]

heatMap =
  styleBox (boxLegend, probScore, impactScore, residualScore)
           True
           ["Rare", "Unlikely", "Possible", "Likely", "Almost certain"]
           ["Negligible", "Minor", "Moderate", "Major", "Severe"]
           bands bands
           xPos yPos
           (risks # { probScore, impactScore, residualScore, riskTitle
                    , ownerName, categoryName, impactUsd, statusName
                    , xPos, yPos })

-- ============================================================== the StyleGrid

-- `StyleGrid a = List (Maybe String, List (Maybe String, a))`: a list of rows,
-- each with an optional CSS class, each holding cells with their own optional
-- class. It is what a writer is handed when a grid's styling is computed rather
-- than declared, and `mapStyleGrid` is its functor -- over the CELL VALUES only,
-- leaving the classes alone.
riskClasses : StyleGrid_SG String
riskClasses =
  [ (Just "risk-row severe", [ (Just "cell hot",  "Cyber intrusion")
                             , (Just "cell hot",  "Regulatory change, EU") ])
  , (Just "risk-row major",  [ (Just "cell warm", "Supplier concentration")
                             , (Just "cell warm", "Freight cost inflation") ])
  , (Nothing,                [ (Nothing,          "Pension deficit") ]) ]

-- The functor: shout every cell, keep every class.
shoutedClasses = mapStyleGrid_SG uppercase_String riskClasses

-- ============================================================== the magnitudes

-- Three units, and they mean different things to a writer. `cells` is a grid
-- unit (a table column, a layout cell), `pixels` is absolute, `dimensionless` is
-- a WEIGHT used to divide leftover space. A `MagnitudeList` is a list of
-- fallbacks: the writer takes the first it understands.
inCells        = [cellsM 12]
inPixels       = [pixelsM 320]
asWeight       = [dimensionlessM 2.0]
withFallbacks  = [cellsM 12, pixelsM 320]

-- `Area` pairs two magnitudes of the SAME unit -- the phantom type parameter on
-- `Magnitude a` is what enforces that, and it is why `Area` has to erase the
-- phantom to exist at all (`Native.Magnitude.erasePhantom`, and the comment
-- there: "unless we erase the phantom, we get skolem variable escapes").
gridArea  = cellsA 20 40
pixelArea = pixelsA 360 640
ratioArea = ratioA 3.0 4.0

-- `Volume` is the three-dimensional form, declared and unused by every writer
-- in the tree -- included here because it is part of the published surface.
someVolume = Volume (cells 2) (cells 3) (cells 4)

sizedHeat  = sizedTo inPixels [pixelsM 420] heatMap
cappedHeat = cappedAt [pixelArea] heatMap

-- ================================================================= the treemap

-- A treemap needs a hierarchy and TWO measures: one for the AREA of each box and
-- one for its COLOUR. `treemapChart`'s constraint is
-- `r <- (labels, ivalue, svalue, r1, r2, o)` -- a partition, hence disjoint --
-- so the intensity column and the size column may not be the same column. Pass
-- the same field twice and the compiler answers
-- "Fields appear twice in row"; `shouldfail/box02_treemap_same_measure.e`
-- records it.
-- The root's impact is the sum of its six children, and each child is the
-- impact total of that category in `risks` above -- 17,230,000 in all. A
-- treemap whose root does not equal its children is the classic way to make one
-- lie, so it is worth checking by hand: 5.31 + 6.48 + 1.95 + 2.24 + 0.80 + 0.45
-- = 17.23 million.
impactTree : [ nodeKey, parentKey, nodeName, nodeImpact, nodeIntensity ]
impactTree = relation [
  { nodeKey = 1, parentKey = 0, nodeName = "All risks",   nodeImpact = 17230000.0, nodeIntensity = 2.6 },
  { nodeKey = 2, parentKey = 1, nodeName = "Operational", nodeImpact =  5310000.0, nodeIntensity = 2.6 },
  { nodeKey = 3, parentKey = 1, nodeName = "Technology",  nodeImpact =  6480000.0, nodeIntensity = 3.3 },
  { nodeKey = 4, parentKey = 1, nodeName = "Financial",   nodeImpact =  1950000.0, nodeIntensity = 1.8 },
  { nodeKey = 5, parentKey = 1, nodeName = "Compliance",  nodeImpact =  2240000.0, nodeIntensity = 2.9 },
  { nodeKey = 6, parentKey = 1, nodeName = "People",      nodeImpact =   800000.0, nodeIntensity = 3.1 },
  { nodeKey = 7, parentKey = 1, nodeName = "Commercial",  nodeImpact =   450000.0, nodeIntensity = 2.4 } ]

impactMap =
  treemapChart parentKey nodeKey nodeName
               (round_Pres 1 nodeIntensity)          -- colour
               (currency_Pres "USD" nodeImpact)       -- area
               impactTree

-- ============================================================== a plain table

riskLegend : Legend_Lg (| riskTitle, ownerName, categoryName, businessUnit
                        , probScore, impactScore, residualScore, impactUsd
                        , mitigationState, statusName |)
riskLegend =
  withFormats ([ (riskTitle,       "Risk")     ^ 0
               , (ownerName,       "Owner")    ^ 1
               , (categoryName,    "Category") ^ 2
               , (businessUnit,    "Unit")     ^ 3
               , (mitigationState, "State")    ^ 4
               , (statusName,      "Status")   ^ 5 ]_Sorted_Lg)
              (round_Fmt 1)
              { probScore, impactScore, residualScore, impactUsd }

riskTable =
  tabular_K ([tabLegend_O := riskLegend]_Opt)
            (risks # { riskTitle, ownerName, categoryName, businessUnit
                     , probScore, impactScore, residualScore, impactUsd
                     , mitigationState, statusName })

byCategory = aggregateByGroup_Agg (sum_Agg (col_Op impactUsd)) {categoryName}
                                  impactUsd risks

-- ==================================================================== the page

heatReport = vflow [
  h2 "Risk register -- probability against impact",
  panel "Heat map" sizedHeat,
  hspan [ panel "Impact by category"
                (pieOf "Impact value" categoryName (currency_Pres "USD" impactUsd)
                       byCategory)
        , panel "Impact treemap" impactMap ],
  h3 "The register",
  riskTable
]
