module Present.VarianceStyling where

{- A STYLED VARIANCE REPORT: budget against actual, with the numbers coloured by
   how far off they are, negatives in parentheses, amounts scaled to thousands,
   fonts and borders set by hand.

   Fact: budgetLines (18 fields: lineId, costCentre, centreName, departmentName,
                      accountCode, accountName, accountGroup, periodName,
                      fiscalYear, budgetAmt, actualAmt, varianceAmt, variancePct,
                      priorYearAmt, forecastAmt, ownerName, currencyCode,
                      approvalStatus)

   WHY THIS FILE EXISTS. `Layout.Format`'s conditional machinery -- `conditional`,
   `colored`, the six `Condition` constructors, `roundParens`, `alias`,
   `markdown`, `constant` -- had NO example anywhere in `core/examples`, and
   neither did `Layout.Font` or `Layout.BorderOptions`. Conditional formatting is
   the single most-asked-for feature of any reporting tool, and in Ermine it is
   not a report-level construct at all: it is a `Format`, i.e. part of a
   `Presentation`, i.e. attached to the COLUMN. That is the lesson of this file.

   THE THING TO NOTICE. A `Format a` is a TREE, not a list of rules: `conditional`
   takes a condition and two formats, either of which may itself be conditional.
   So a three-band rule is two nested conditionals, and the bands are checked in
   the order you nest them -- there is no rule table and no priority. `bandedBy`
   in `Helpers.e` is that nesting, named.

   AND: the format is attached to the presentation, so the RELATION is untouched.
   The database still holds a signed number in dollars; the reader sees `(1.2)`
   in red in thousands. Filters and joins keep working on the real value. Compare
   `scaledBy`, which does change the relation, and must, because a scaled number
   is a different number.

   SHAPES EXERCISED
     * `styledBy` (two-way) and `bandedBy` (three-way nested `conditional`)
       instantiated against a bare field, a computed difference and a ratio.
     * `Layout.Format.alias` -- a display lookup table that leaves the code in
       the relation, so `filterEq approvalStatus "Escalated"` still works.
     * `accounting` = `roundParens' True`: negatives in parentheses, coloured.
     * `Layout.Font`: `atom'` with an explicit font stack and point size, and
       `Layout.BorderOptions` through `borderSize'`.
     * `scaledBy` in two magnitudes -- thousands and millions -- on the same
       column, showing that the SCALE is a relational operation and the FORMAT
       is not.
     * `Layout.Magnitude` in its real sense: `sizedTo`, `cappedAt`, `fixW`.
     * A `Legend` built by `withFormats` from a key legend and a measure row,
       then re-prioritised by `pinned` and grouped by `groupedAs`.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/VarianceStyling.e
     >> varianceReport
     >> inThousands

   There is no `render`; evaluate the report and the relations. See
   `tracker/loopmodel/E4-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Color
import Layout.Font
import Layout.Magnitude
import Layout.BorderOptions as BOpt
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Native.BorderOptions as BO
import Relation.Op as Op
import Relation.Aggregate as Agg
import Relation.Predicate as Pred
import Relation.Sort as Sort
import Syntax.Relation
import Syntax.List
import Present.Helpers

field lineId : Int
field costCentre, centreName, departmentName : String
field accountCode, accountName, accountGroup : String
field periodName, fiscalYear, ownerName, currencyCode, approvalStatus : String
field budgetAmt, actualAmt, varianceAmt, variancePct : Double
field priorYearAmt, forecastAmt : Double

field budgetK, actualK, varianceK, budgetM : Double
field yoyPct, forecastGap : Double

-- ------------------------------------------------------------- the fact table

-- Eighteen columns, fourteen budget lines, four cost centres, two periods.
budgetLines : [ lineId, costCentre, centreName, departmentName, accountCode
              , accountName, accountGroup, periodName, fiscalYear, budgetAmt
              , actualAmt, varianceAmt, variancePct, priorYearAmt, forecastAmt
              , ownerName, currencyCode, approvalStatus ]
budgetLines = relation [
  { lineId = 1, costCentre = "CC-100", centreName = "Manufacturing", departmentName = "Operations",
    accountCode = "6100", accountName = "Raw materials", accountGroup = "COGS", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 480000.0, actualAmt = 512400.0, varianceAmt = 32400.0,
    variancePct = 0.0675, priorYearAmt = 441000.0, forecastAmt = 505000.0, ownerName = "m.iverson",
    currencyCode = "USD", approvalStatus = "Approved" },
  { lineId = 2, costCentre = "CC-100", centreName = "Manufacturing", departmentName = "Operations",
    accountCode = "6110", accountName = "Direct labour", accountGroup = "COGS", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 310000.0, actualAmt = 297300.0, varianceAmt = -12700.0,
    variancePct = -0.0410, priorYearAmt = 288000.0, forecastAmt = 300000.0, ownerName = "m.iverson",
    currencyCode = "USD", approvalStatus = "Approved" },
  { lineId = 3, costCentre = "CC-100", centreName = "Manufacturing", departmentName = "Operations",
    accountCode = "7200", accountName = "Plant maintenance", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 96000.0, actualAmt = 148900.0, varianceAmt = 52900.0,
    variancePct = 0.5510, priorYearAmt = 91000.0, forecastAmt = 120000.0, ownerName = "m.iverson",
    currencyCode = "USD", approvalStatus = "Escalated" },
  { lineId = 4, costCentre = "CC-210", centreName = "Field sales", departmentName = "Commercial",
    accountCode = "7310", accountName = "Travel", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 64000.0, actualAmt = 41200.0, varianceAmt = -22800.0,
    variancePct = -0.3563, priorYearAmt = 70000.0, forecastAmt = 55000.0, ownerName = "p.nakamura",
    currencyCode = "USD", approvalStatus = "Approved" },
  { lineId = 5, costCentre = "CC-210", centreName = "Field sales", departmentName = "Commercial",
    accountCode = "7320", accountName = "Entertainment", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 18000.0, actualAmt = 26700.0, varianceAmt = 8700.0,
    variancePct = 0.4833, priorYearAmt = 15500.0, forecastAmt = 22000.0, ownerName = "p.nakamura",
    currencyCode = "USD", approvalStatus = "Pending" },
  { lineId = 6, costCentre = "CC-210", centreName = "Field sales", departmentName = "Commercial",
    accountCode = "7400", accountName = "Commissions", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 145000.0, actualAmt = 151200.0, varianceAmt = 6200.0,
    variancePct = 0.0428, priorYearAmt = 132000.0, forecastAmt = 150000.0, ownerName = "p.nakamura",
    currencyCode = "USD", approvalStatus = "Approved" },
  { lineId = 7, costCentre = "CC-330", centreName = "Platform", departmentName = "Technology",
    accountCode = "7500", accountName = "Cloud hosting", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 220000.0, actualAmt = 286500.0, varianceAmt = 66500.0,
    variancePct = 0.3023, priorYearAmt = 164000.0, forecastAmt = 250000.0, ownerName = "a.silva",
    currencyCode = "USD", approvalStatus = "Escalated" },
  { lineId = 8, costCentre = "CC-330", centreName = "Platform", departmentName = "Technology",
    accountCode = "7510", accountName = "Software licences", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 88000.0, actualAmt = 84100.0, varianceAmt = -3900.0,
    variancePct = -0.0443, priorYearAmt = 79000.0, forecastAmt = 86000.0, ownerName = "a.silva",
    currencyCode = "USD", approvalStatus = "Approved" },
  { lineId = 9, costCentre = "CC-330", centreName = "Platform", departmentName = "Technology",
    accountCode = "7520", accountName = "Contractors", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 130000.0, actualAmt = 92800.0, varianceAmt = -37200.0,
    variancePct = -0.2862, priorYearAmt = 148000.0, forecastAmt = 110000.0, ownerName = "a.silva",
    currencyCode = "USD", approvalStatus = "Approved" },
  { lineId = 10, costCentre = "CC-440", centreName = "Corporate", departmentName = "Corporate",
    accountCode = "7600", accountName = "Legal", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 45000.0, actualAmt = 78300.0, varianceAmt = 33300.0,
    variancePct = 0.7400, priorYearAmt = 39000.0, forecastAmt = 60000.0, ownerName = "l.dubois",
    currencyCode = "USD", approvalStatus = "Escalated" },
  { lineId = 11, costCentre = "CC-440", centreName = "Corporate", departmentName = "Corporate",
    accountCode = "7610", accountName = "Audit", accountGroup = "Opex", periodName = "Jan",
    fiscalYear = "FY2011", budgetAmt = 52000.0, actualAmt = 51400.0, varianceAmt = -600.0,
    variancePct = -0.0115, priorYearAmt = 50000.0, forecastAmt = 52000.0, ownerName = "l.dubois",
    currencyCode = "USD", approvalStatus = "Approved" },
  { lineId = 12, costCentre = "CC-100", centreName = "Manufacturing", departmentName = "Operations",
    accountCode = "6100", accountName = "Raw materials", accountGroup = "COGS", periodName = "Feb",
    fiscalYear = "FY2011", budgetAmt = 490000.0, actualAmt = 478900.0, varianceAmt = -11100.0,
    variancePct = -0.0227, priorYearAmt = 455000.0, forecastAmt = 485000.0, ownerName = "m.iverson",
    currencyCode = "USD", approvalStatus = "Approved" },
  { lineId = 13, costCentre = "CC-210", centreName = "Field sales", departmentName = "Commercial",
    accountCode = "7310", accountName = "Travel", accountGroup = "Opex", periodName = "Feb",
    fiscalYear = "FY2011", budgetAmt = 64000.0, actualAmt = 88600.0, varianceAmt = 24600.0,
    variancePct = 0.3844, priorYearAmt = 72000.0, forecastAmt = 70000.0, ownerName = "p.nakamura",
    currencyCode = "USD", approvalStatus = "Pending" },
  { lineId = 14, costCentre = "CC-330", centreName = "Platform", departmentName = "Technology",
    accountCode = "7500", accountName = "Cloud hosting", accountGroup = "Opex", periodName = "Feb",
    fiscalYear = "FY2011", budgetAmt = 230000.0, actualAmt = 241100.0, varianceAmt = 11100.0,
    variancePct = 0.0483, priorYearAmt = 171000.0, forecastAmt = 240000.0, ownerName = "a.silva",
    currencyCode = "USD", approvalStatus = "Approved" }]

-- ================================================================== the scales

-- THE SCALE IS RELATIONAL. `scaledBy` divides and keeps the row; the resulting
-- relation carries a different number, and that is honest -- a report "in
-- thousands" really does show a different number from the ledger.
inThousands : [ lineId, costCentre, centreName, accountName, accountGroup, periodName
         , budgetK, actualK, varianceK, variancePct, budgetM, yoyPct, forecastGap
         , approvalStatus, ownerName ]
inThousands =
     budgetLines
  |> combine_Op (scaledBy 1000.0 budgetAmt)   budgetK
  |> combine_Op (scaledBy 1000.0 actualAmt)   actualK
  |> combine_Op (scaledBy 1000.0 varianceAmt) varianceK
  |> combine_Op (scaledBy 1000000.0 budgetAmt) budgetM
  |> combine_Op ((asOp_Op actualAmt -_Op asOp_Op priorYearAmt) /_Op asOp_Op priorYearAmt) yoyPct
  |> combine_Op ((asOp_Op actualAmt -_Op asOp_Op forecastAmt) /_Op asOp_Op forecastAmt) forecastGap
  |> except { departmentName, accountCode, fiscalYear, budgetAmt, actualAmt
            , varianceAmt, priorYearAmt, forecastAmt, currencyCode }

-- ============================================================== the format rules

-- TWO-WAY. The VARIANCE at or above zero in red, below it in green. Note the
-- direction: for an EXPENSE, over budget is bad, so the "good" colour goes to
-- the lower band. (The name says what it presents -- `varianceK` -- because a
-- presentation named after the wrong column is the easiest way to mislabel a
-- grid.)
varianceAmountPres = styledBy 0.0 (rgb 176 42 30) (rgb 22 122 60) (accounting 1) varianceK

-- THREE-WAY, nested. Under 2 % off in grey, 2-10 % in amber, over 10 % in red.
-- `bandedBy lo hi bad mid good` reads "below lo is bad, at or above hi is good";
-- here the sense is inverted by passing the colours the other way round, which
-- is exactly what a reader should have to do consciously.
variancePres = bandedBy 0.02 0.10 (rgb 90 90 90) (rgb 196 132 12) (rgb 176 42 30)
                        percentage_Fmt variancePct

-- A ratio, coloured against a target of zero drift from forecast.
forecastPres = styledBy 0.0 (rgb 176 42 30) (rgb 22 122 60)
                        (percentageRoundParens_Fmt 1) forecastGap

-- A DISPLAY LOOKUP. The relation still carries "Escalated"; the reader sees the
-- long form. `Format.alias` is a format, not an `Op`, so
-- `filterEq approvalStatus "Escalated"` below still finds the rows.
statusPres = aliasedBy [ ("Approved",  "Approved")
                       , ("Pending",   "Awaiting sign-off")
                       , ("Escalated", "**Escalated to the CFO**") ]
                       approvalStatus

-- A constant format: the column's value is ignored and one string is shown.
-- Useful for a spacer column or a units marker.
unitsPres = presentation_Pres (constant_Fmt "$000") budgetK

-- ================================================================== the legend

-- The keys are labelled by hand and given an initial sort; the five measure
-- columns share one rounding format, supplied to `withFormats` as a `Row`.
-- `withFormats`'s partition `r <- (k, m)` checks that the two halves cover the
-- grid exactly -- forget a column and the legend does not type-check.
gridLegend : Legend_Lg (| costCentre, centreName, accountName, periodName
                        , budgetK, actualK, varianceK, budgetM |)
gridLegend =
  withFormats ([ (costCentre,  "Centre")  ^ 0
               , (centreName,  "Name")    ^ 1
               , (accountName, "Account") ^ 2
               , (periodName,  "Period")  ^ 3 ]_Sorted_Lg)
              (round_Fmt 1)
              { budgetK, actualK, varianceK, budgetM }

-- The fully hand-built legend, one labelled presentation at a time, so every
-- column gets its OWN format. `labelled` is `Layout.Legend.legend` plus `(++)`,
-- and each application carries the partition that says the column is new.
styledLegend : Legend_Lg (| costCentre, accountName, periodName, budgetK, varianceK
                          , variancePct, forecastGap, approvalStatus |)
styledLegend =
  ( labelled costCentre               "Centre"
  . labelled accountName              "Account"
  . labelled periodName               "Period"
  . labelled (round_Pres 1 budgetK)   "Budget $000"
  . labelled varianceAmountPres       "Variance $000"
  . labelled variancePres             "Variance %"
  . labelled forecastPres             "vs forecast"
  . labelled statusPres               "Status"
  ) empty_Lg

-- Re-prioritise one column's place in the INITIAL sort without rebuilding the
-- legend, and put the money columns under a spanning heading.
sortedLegend = groupedAs "Fiscal 2011, January to February"
                 (pinned "Variance %" (descending 0) styledLegend)

-- A legend built from a ROW plus a naming FUNCTION. `relabelled` is the right
-- tool when the column names are systematic and the display names are derived
-- from them -- a warehouse whose columns are `amt_usd_ttm` and `amt_usd_ytd`
-- wants one function, not one `labelled` per column. `legendFor` supplies the
-- keys' default legend, and `(++)`'s partition checks the two halves are
-- disjoint.
displayName n = if (n == "budgetK")   "Budget"
                   (if (n == "actualK")   "Actual"
                      (if (n == "varianceK") "Variance" n))

autoLegend : Legend_Lg (| costCentre, accountName, periodName
                        , budgetK, actualK, varianceK |)
autoLegend =
  legendFor {costCentre, accountName, periodName}
    ++_Lg groupedAs "$000" (relabelled displayName {budgetK, actualK, varianceK})

-- =================================================================== the grids

autoGrid = tabular_K ([tabLegend_O := autoLegend]_Opt)
                     (inThousands # { costCentre, accountName, periodName
                                    , budgetK, actualK, varianceK })

plainGrid = tabular_K ([tabLegend_O := gridLegend]_Opt)
                      (inThousands # { costCentre, centreName, accountName, periodName
                                , budgetK, actualK, varianceK, budgetM })

styledGrid = tabular_K ([tabLegend_O := sortedLegend]_Opt)
                       (inThousands # { costCentre, accountName, periodName, budgetK
                                 , varianceK, variancePct, forecastGap
                                 , approvalStatus })

-- The alias is a FORMAT, so the underlying code is still there to filter on.
escalated = inThousands |> filterEq approvalStatus "Escalated"
escalatedGrid = tabular_K ([tabLegend_O := sortedLegend]_Opt)
                          (escalated # { costCentre, accountName, periodName
                                       , budgetK, varianceK, variancePct
                                       , forecastGap, approvalStatus })

-- ============================================================= fonts and borders

-- `atom'` takes a FONT STACK -- the first that the medium has, then fallbacks --
-- and an optional point size. `Layout.Font` gives both named faces and generic
-- genres, and a genre is the right thing to ask for when the medium is unknown.
bigNumber v = atom' [gillSans, humanist, sansSerif] (Just 28) (Atomic (round_Fmt 1) v)
caption   s = atom' [dejaVuSans, sansSerif] (Just 10) (Atomic unit_Fmt s)
codeLine  s = atom' [monospaced] (Just 11) (Atomic verbatim_Fmt s)

-- `borderSize'` takes an ENDOMORPHISM on a `BorderOptions`, so a border is
-- built by composing the four side-setters -- `top`, `right`, `bottom`, `left`
-- from `Layout.BorderOptions` -- rather than by passing four maybes.
ruled r = borderSize' (top_BOpt (solid_BO, thin_BO) . bottom_BOpt (solid_BO, medium_BO)) r
boxed r = borderSize solid_BO thin_BO r

-- ==================================================================== the page

-- `cappedAt` bounds the grid rather than suggesting a size; `fixW` fixes the
-- caption column so the tiles line up.
tile capt v = boxed (vflow [ centered (bigNumber v)
                           , centered (fixW [pixelsM 140] (caption capt)) ])

-- THE TILES ARE COMPUTED. `scanRelation` executes the relation and hands the
-- rows over as values, so the three headline numbers come from the same fourteen
-- lines the grids draw. Typed in by hand they were all three wrong, which is the
-- argument for never typing a total into a heading.
tiles = scanRelation (budgetLines # { lineId, budgetAmt, actualAmt, varianceAmt })
                     (rows ->
  let totalOf f = sum' (map (r -> r ! f) rows) / 1000.0
  in hspan [ tile "Budget $000"   (totalOf budgetAmt)
           , tile "Actual $000"   (totalOf actualAmt)
           , tile "Variance $000" (totalOf varianceAmt) ])

varianceReport = vflow [
  h2 "Variance to budget -- fiscal 2011, January and February",
  tiles,
  vstrut,
  ruled (h3 "Every line, plain"),
  cappedAt [pixelsA 900 320] plainGrid,
  vstrut,
  ruled (h3 "The same columns, named by a function rather than one at a time"),
  autoGrid,
  vstrut,
  ruled (h3 "Every line, conditionally formatted"),
  cappedAt [pixelsA 900 320] styledGrid,
  vstrut,
  ruled (h3 "Escalated only -- the alias is a format, so the code still filters"),
  escalatedGrid,
  vstrut,
  codeLine "escalated = inThousands |> filterEq approvalStatus \"Escalated\""
]
