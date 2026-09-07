module Time.CohortRetention where

{- A COHORT RETENTION TRIANGLE: signup month down the side, months-since-signup
   across the top, and the count (and revenue) still active in each cell.

   Fact: activity (16 fields: activityId, accountId, accountName, cohortLabel,
                   segment, region, plan, channel, ownerRep, healthScore, seats,
                   signupDate, activityDate, mrr, churnRisk, lastLoginDays)

   THE TRIANGLE IS NOT A PIVOT. `Relation.Pivot` would need the tenure values as
   a static list; here they are DERIVED from the data by a date difference and
   the report must lay out whatever comes back. `Layout.Scan`'s `columns` does
   that: group the relation by the tenure month, turn each group into a column,
   and key the rows by the cohort. The shape is triangular for the honest reason
   -- a cohort that signed up in April cannot have a month-5 cell in a window
   that ends in June -- and the layout simply has no cell there.

   SHAPES EXERCISED
     * `monthsBetween` and `monthsSince` -- both period indices come from
       `dateDiff`, because `Relation.Op` has no month accessor.
     * `Relation.Aggregate.aggregateByGroup` -- group and aggregate in ONE call,
       with the grouping given as a `Row`, and no `materialize` needed because it
       does not go through `Relation.groupBy`'s `Mem`. (`core/examples/Present/`
       uses it too, concurrently with this directory; nothing did before.)
     * `Layout.Scan`'s `groupBy1` / `mapV` / `column` / `columns` / `keys` --
       the derived-column-set layout.
     * `Layout.Report.Keyed.tabular` with a `Layout.Legend` pinning the column
       order and headings.
     * `indexOf` -- the ratio form of period-over-period change.
     * `safeDiv` -- a cohort with no month-0 revenue would divide by zero.

     >> :load core/examples/Time/Helpers.e
     >> :load core/examples/Time/CohortRetention.e
     >> cohortReport

   NOTE ON `render`. `render` is not a defined term anywhere in Ermine -- not in
   the stdlib, not in the REPL. A report can only be RENDERED through
   `Layout.harness`, which needs a `Scanner` and a `Runner`, and every
   constructor of both is a database connection. So from `bin/ermine` you
   EVALUATE the report (and any relation in the module), which prints its
   resolved header -- the column set the report will show. See
   `tracker/loopmodel/E3-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Layout.Scan
import Layout.Legend as Lg
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Time.Helpers

field activityId, accountId, healthScore, seats, lastLoginDays : Int
field accountName, cohortLabel, segment, region, plan, channel : String
field ownerRep, churnRisk : String
field signupDate, activityDate : Date
field mrr : Double
field tenureMonth, cohortIx : Int
field activeAccounts, baseAccounts, retentionRate : Double
field cohortMrr, baseMrr, mrrRetention : Double

-- ------------------------------------------------------------- the fact table

-- Sixteen columns. One row per account per month it was still active. Three
-- cohorts -- January, February and April 2011 -- observed to June.
activity : [ activityId, accountId, accountName, cohortLabel, segment, region
           , plan, channel, ownerRep, healthScore, seats, signupDate
           , activityDate, mrr, churnRisk, lastLoginDays ]
activity = relation [
  { activityId = 1, accountId = 900, accountName = "Northwind Traders",
    cohortLabel = "2011-01", segment = "Enterprise", region = "AMER",
    plan = "Platform", channel = "Direct", ownerRep = "j.okafor",
    healthScore = 82, seats = 240, signupDate = @2011/1/12,
    activityDate = @2011/1/31, mrr = 18400.0, churnRisk = "Low", lastLoginDays = 1 },
  { activityId = 2, accountId = 900, accountName = "Northwind Traders",
    cohortLabel = "2011-01", segment = "Enterprise", region = "AMER",
    plan = "Platform", channel = "Direct", ownerRep = "j.okafor",
    healthScore = 84, seats = 240, signupDate = @2011/1/12,
    activityDate = @2011/2/28, mrr = 18400.0, churnRisk = "Low", lastLoginDays = 2 },
  { activityId = 3, accountId = 900, accountName = "Northwind Traders",
    cohortLabel = "2011-01", segment = "Enterprise", region = "AMER",
    plan = "Platform", channel = "Direct", ownerRep = "j.okafor",
    healthScore = 88, seats = 300, signupDate = @2011/1/12,
    activityDate = @2011/3/31, mrr = 23000.0, churnRisk = "Low", lastLoginDays = 1 },
  { activityId = 4, accountId = 900, accountName = "Northwind Traders",
    cohortLabel = "2011-01", segment = "Enterprise", region = "AMER",
    plan = "Platform", channel = "Direct", ownerRep = "j.okafor",
    healthScore = 86, seats = 300, signupDate = @2011/1/12,
    activityDate = @2011/4/30, mrr = 23000.0, churnRisk = "Low", lastLoginDays = 3 },
  { activityId = 5, accountId = 901, accountName = "Wide World Importers",
    cohortLabel = "2011-01", segment = "Mid-market", region = "EMEA",
    plan = "Business", channel = "Partner", ownerRep = "m.lindqvist",
    healthScore = 61, seats = 70, signupDate = @2011/1/25,
    activityDate = @2011/1/31, mrr = 4900.0, churnRisk = "Medium", lastLoginDays = 4 },
  { activityId = 6, accountId = 901, accountName = "Wide World Importers",
    cohortLabel = "2011-01", segment = "Mid-market", region = "EMEA",
    plan = "Business", channel = "Partner", ownerRep = "m.lindqvist",
    healthScore = 54, seats = 70, signupDate = @2011/1/25,
    activityDate = @2011/2/28, mrr = 4900.0, churnRisk = "High", lastLoginDays = 19 },
  { activityId = 7, accountId = 902, accountName = "Contoso GmbH",
    cohortLabel = "2011-02", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Partner", ownerRep = "m.lindqvist",
    healthScore = 77, seats = 130, signupDate = @2011/2/8,
    activityDate = @2011/2/28, mrr = 9750.0, churnRisk = "Low", lastLoginDays = 1 },
  { activityId = 8, accountId = 902, accountName = "Contoso GmbH",
    cohortLabel = "2011-02", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Partner", ownerRep = "m.lindqvist",
    healthScore = 79, seats = 130, signupDate = @2011/2/8,
    activityDate = @2011/3/31, mrr = 9750.0, churnRisk = "Low", lastLoginDays = 2 },
  { activityId = 9, accountId = 902, accountName = "Contoso GmbH",
    cohortLabel = "2011-02", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Partner", ownerRep = "m.lindqvist",
    healthScore = 75, seats = 110, signupDate = @2011/2/8,
    activityDate = @2011/4/30, mrr = 8250.0, churnRisk = "Medium", lastLoginDays = 6 },
  { activityId = 10, accountId = 903, accountName = "Adatum Media",
    cohortLabel = "2011-02", segment = "Mid-market", region = "AMER",
    plan = "Business", channel = "Self-serve", ownerRep = "s.ahmed",
    healthScore = 68, seats = 45, signupDate = @2011/2/17,
    activityDate = @2011/2/28, mrr = 3150.0, churnRisk = "Medium", lastLoginDays = 2 },
  { activityId = 11, accountId = 903, accountName = "Adatum Media",
    cohortLabel = "2011-02", segment = "Mid-market", region = "AMER",
    plan = "Business", channel = "Self-serve", ownerRep = "s.ahmed",
    healthScore = 70, seats = 45, signupDate = @2011/2/17,
    activityDate = @2011/3/31, mrr = 3150.0, churnRisk = "Low", lastLoginDays = 1 },
  { activityId = 12, accountId = 904, accountName = "Litware Bank",
    cohortLabel = "2011-02", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Direct", ownerRep = "a.petrova",
    healthScore = 91, seats = 310, signupDate = @2011/2/23,
    activityDate = @2011/2/28, mrr = 24800.0, churnRisk = "Low", lastLoginDays = 1 },
  { activityId = 13, accountId = 904, accountName = "Litware Bank",
    cohortLabel = "2011-02", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Direct", ownerRep = "a.petrova",
    healthScore = 92, seats = 310, signupDate = @2011/2/23,
    activityDate = @2011/3/31, mrr = 24800.0, churnRisk = "Low", lastLoginDays = 1 },
  { activityId = 14, accountId = 904, accountName = "Litware Bank",
    cohortLabel = "2011-02", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Direct", ownerRep = "a.petrova",
    healthScore = 93, seats = 365, signupDate = @2011/2/23,
    activityDate = @2011/4/30, mrr = 29200.0, churnRisk = "Low", lastLoginDays = 1 },
  { activityId = 15, accountId = 904, accountName = "Litware Bank",
    cohortLabel = "2011-02", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Direct", ownerRep = "a.petrova",
    healthScore = 90, seats = 365, signupDate = @2011/2/23,
    activityDate = @2011/5/31, mrr = 29200.0, churnRisk = "Low", lastLoginDays = 2 },
  { activityId = 16, accountId = 905, accountName = "Fabrikam Ltd",
    cohortLabel = "2011-04", segment = "SMB", region = "EMEA",
    plan = "Team", channel = "Self-serve", ownerRep = "a.petrova",
    healthScore = 58, seats = 25, signupDate = @2011/4/5,
    activityDate = @2011/4/30, mrr = 1875.0, churnRisk = "Medium", lastLoginDays = 3 },
  { activityId = 17, accountId = 905, accountName = "Fabrikam Ltd",
    cohortLabel = "2011-04", segment = "SMB", region = "EMEA",
    plan = "Team", channel = "Self-serve", ownerRep = "a.petrova",
    healthScore = 49, seats = 25, signupDate = @2011/4/5,
    activityDate = @2011/5/31, mrr = 1875.0, churnRisk = "High", lastLoginDays = 21 },
  { activityId = 18, accountId = 906, accountName = "Trey Logistics",
    cohortLabel = "2011-04", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Direct", ownerRep = "m.lindqvist",
    healthScore = 85, seats = 165, signupDate = @2011/4/24,
    activityDate = @2011/4/30, mrr = 12375.0, churnRisk = "Low", lastLoginDays = 1 },
  { activityId = 19, accountId = 906, accountName = "Trey Logistics",
    cohortLabel = "2011-04", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Direct", ownerRep = "m.lindqvist",
    healthScore = 87, seats = 165, signupDate = @2011/4/24,
    activityDate = @2011/5/31, mrr = 12375.0, churnRisk = "Low", lastLoginDays = 2 },
  { activityId = 20, accountId = 906, accountName = "Trey Logistics",
    cohortLabel = "2011-04", segment = "Enterprise", region = "EMEA",
    plan = "Platform", channel = "Direct", ownerRep = "m.lindqvist",
    healthScore = 88, seats = 190, signupDate = @2011/4/24,
    activityDate = @2011/6/30, mrr = 14250.0, churnRisk = "Low", lastLoginDays = 1 }
]

-- ================================================================ the pipeline

-- STEP 1. Both period indices, derived. `tenureMonth` is the number of whole
-- months from signup to the activity month -- 0 for the signup month itself --
-- and `cohortIx` is a dense INTEGER index over the cohorts themselves, which is
-- what lets a chart or a sort order the cohorts as numbers rather than as the
-- strings `cohortLabel` carries.
cohortIndexed =
     activity
  |> combine_Op (monthsBetween signupDate activityDate) tenureMonth
  |> combine_Op (monthsSince @2010/12/1 signupDate) cohortIx

-- STEP 2. The cells. `aggregateByGroup` groups and aggregates in one call, with
-- the grouping row given as a `Row` -- no `groupBy` / `materialize` pair.
cohortCounts : [ cohortLabel, tenureMonth, activeAccounts ]
cohortCounts =
  aggregateByGroup_Agg countAgg_Agg {cohortLabel, tenureMonth} activeAccounts cohortIndexed

-- and the same cells keyed by the integer cohort index. This is `cohortIx`'s
-- reason to exist, and without it the column would be dead.
cohortCountsByIx : [ cohortIx, tenureMonth, activeAccounts ]
cohortCountsByIx =
  aggregateByGroup_Agg countAgg_Agg {cohortIx, tenureMonth} activeAccounts cohortIndexed

cohortRevenue : [ cohortLabel, tenureMonth, cohortMrr ]
cohortRevenue =
  aggregateByGroup_Agg (sum_Agg (col_Op mrr)) {cohortLabel, tenureMonth}
                       cohortMrr cohortIndexed

-- STEP 3. Each cohort's month-0 row, as the denominator.
baseCounts : [ cohortLabel, baseAccounts ]
baseCounts = filterEq tenureMonth 0 cohortCounts
          |> except {tenureMonth}
          |> rename activeAccounts baseAccounts

baseRevenue : [ cohortLabel, baseMrr ]
baseRevenue = filterEq tenureMonth 0 cohortRevenue
           |> except {tenureMonth}
           |> rename cohortMrr baseMrr

-- STEP 4. The rates. `indexOf` is `cur / prior`; `safeDiv` guards the revenue
-- one, because a cohort could in principle have signed up on free trials and
-- had zero month-0 revenue.
retention =
  combine_Op (indexOf activeAccounts baseAccounts) retentionRate
             (join cohortCounts baseCounts)

revenueRetention =
  combine_Op (safeDiv cohortMrr baseMrr) mrrRetention
             (join cohortRevenue baseRevenue)

-- ============================================================== the triangle

-- ONE COLUMN PER TENURE MONTH, rows keyed by cohort. `groupBy1` from
-- `Layout.Scan` splits the relation on the tenure month; `mapV column` turns
-- each group into a column of the grid; `columns ... keys {cohortLabel}` lays
-- the columns out against the cohort key. Cells that do not exist -- April's
-- month 4, say -- are simply absent.
retentionTriangle =
  groupBy1 tenureMonth cohortCounts
    |> mapV column
    |> columns '
       keys { cohortLabel }

-- The same for the rate rather than the count.
rateTriangle =
  groupBy1 tenureMonth (retention # {cohortLabel, tenureMonth, retentionRate})
    |> mapV column
    |> columns '
       keys { cohortLabel }

-- And for revenue.
revenueTriangle =
  groupBy1 tenureMonth cohortRevenue
    |> mapV column
    |> columns '
       keys { cohortLabel }

-- ----------------------------------------------------- a Keyed tabular

-- `Layout.Report.Keyed.tabular` with a legend that pins BOTH the order and the
-- headings -- the flat form of the same numbers, for a reader who wants the
-- cells as rows.
retentionLegend : Legend_Lg (| cohortLabel, tenureMonth, activeAccounts, retentionRate |)
retentionLegend = [ (cohortLabel,    "Cohort")           ^ 0
                  , (tenureMonth,    "Months since")     ^ 1
                  , (activeAccounts, "Accounts active")  ^ 2
                  , (retentionRate,  "Retention")        ^ 3 ]_Sorted_Lg

retentionTable =
  tabular_K ([tabLegend_O := retentionLegend]_Opt)
            (retention # {cohortLabel, tenureMonth, activeAccounts, retentionRate})

-- ------------------------------------------------------------------- report

cohortReport = vflow [
  atomShown "## Cohort retention, signups January to April 2011",
  atomShown "### Accounts still active, cohort x months since signup",
  retentionTriangle,
  atomShown "### Retention rate against the cohort's own month 0",
  rateTriangle,
  atomShown "### Revenue retention",
  revenueTriangle,
  atomShown "### The same cells as rows",
  retentionTable,
  atomShown "### Revenue retention, flat",
  tabular Nothing revenueRetention,
  atomShown "### The same cells keyed by the integer cohort index",
  tabular Nothing cohortCountsByIx
]
