module Wide.MediaSpend where

{- MEDIA SPEND PIVOTED BY CHANNEL, WITH DEFAULTS FOR THE CELLS THAT ARE MISSING.

   A pivot has a hole problem the long form does not: if a campaign bought no
   audio in March, there is no March/audio row, and the pivoted table has a gap
   where a number should be.  A null there is worse than useless -- it poisons
   every sum across the row.  `pivotOnRowWithDefault` fills those cells from the
   produced column's TYPE, which for a Double is zero.

   The module also shows the CONCISE pivot spelling.  `pivotColumn` names each
   produced column, its key value and its value Op separately, which is what you
   need when the key values are not legal field names.  When they are --
   "search", "social", "display" -- `pivotOnRow` takes the whole produced row at
   once and matches on the field names, and a five-column pivot is one line.

   Fact:       spend (23 columns)
                 keys      spendId, campaignId, channelId, monthName
                 money     spendUsd, revenueUsd, cpmUsd, cpcUsd, cpaUsd, roas
                 volume    impressions, clicks, conversions, reachCount,
                           frequency
                 quality   viewabilityPct, bounceRatePct, videoCompletionPct,
                           brandLiftPct
                 setup     creativeCount, audienceSize, bidStrategy,
                           placementName
   Dimensions: campaign (campaignId -> campaignName, objective)
               channel  (channelId  -> channelName)

   Helpers used: pivotOnRow, pivotOnRowWithDefault, pivotBy, pivotByWithDefault,
                 topNWithin, desc (Wide.Helpers).

   Solver shapes exercised:
     * `defaultFulcrum`'s row-driven plan: the produced row `p` is given WHOLE
       rather than built one `consFulcrum` at a time, so `s <- (i, p)` is solved
       against a five-field concrete `p` in one step instead of five;
     * the same pivot twice, once defaulted and once not, so the identical
       existential `i` is minted by two different code paths;
     * `topNWithin` over a 26-column joined row, whose `t <- (c, u)` re-partitions
       the row the same call minted.

   The pivots TYPE-CHECK but cannot be evaluated here: `Relation.Pivot.pivot`
   panics when forced (section 7.2 of `tracker/loopmodel/E1-EXAMPLES.md`).

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/MediaSpend.e
     >> :type spendByChannel
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field spendId, campaignId, channelId : Int
field impressions, clicks, conversions, reachCount, creativeCount, audienceSize : Int
field spendUsd, revenueUsd, cpmUsd, cpcUsd, cpaUsd, roas : Double
field viewabilityPct, bounceRatePct, videoCompletionPct, brandLiftPct, frequency : Double
field monthName, bidStrategy, placementName : String
field campaignName, objective, channelName : String
field search, social, display, video, audio : Double
field spendRank : Int

-- Twenty-three columns.  Fourteen rows: two campaigns, three months, and
-- deliberately NOT every channel in every month -- that is the point.
spend = relation [
  { spendId = 1, campaignId = 1, channelId = 1, monthName = "Jan",
    spendUsd = 84000.0, revenueUsd = 310000.0, cpmUsd = 6.10, cpcUsd = 1.42,
    cpaUsd = 38.20, roas = 3.69,
    impressions = 13770000, clicks = 59150, conversions = 2199, reachCount = 4210000,
    frequency = 3.27, viewabilityPct = 71.4, bounceRatePct = 42.1,
    videoCompletionPct = 0.0, brandLiftPct = 1.8,
    creativeCount = 12, audienceSize = 9100000, bidStrategy = "tCPA",
    placementName = "Top of page" },
  { spendId = 2, campaignId = 1, channelId = 2, monthName = "Jan",
    spendUsd = 51000.0, revenueUsd = 128000.0, cpmUsd = 4.40, cpcUsd = 0.88,
    cpaUsd = 61.40, roas = 2.51,
    impressions = 11590000, clicks = 57950, conversions = 831, reachCount = 3880000,
    frequency = 2.99, viewabilityPct = 64.2, bounceRatePct = 55.8,
    videoCompletionPct = 0.0, brandLiftPct = 3.1,
    creativeCount = 24, audienceSize = 14200000, bidStrategy = "Reach",
    placementName = "In-feed" },
  { spendId = 3, campaignId = 1, channelId = 3, monthName = "Jan",
    spendUsd = 22000.0, revenueUsd = 41000.0, cpmUsd = 2.10, cpcUsd = 2.94,
    cpaUsd = 152.80, roas = 1.86,
    impressions = 10480000, clicks = 7480, conversions = 144, reachCount = 5910000,
    frequency = 1.77, viewabilityPct = 48.9, bounceRatePct = 68.0,
    videoCompletionPct = 0.0, brandLiftPct = 0.9,
    creativeCount = 8, audienceSize = 22000000, bidStrategy = "vCPM",
    placementName = "Sidebar" },
  { spendId = 4, campaignId = 1, channelId = 1, monthName = "Feb",
    spendUsd = 91000.0, revenueUsd = 352000.0, cpmUsd = 6.25, cpcUsd = 1.38,
    cpaUsd = 36.10, roas = 3.87,
    impressions = 14560000, clicks = 65940, conversions = 2521, reachCount = 4380000,
    frequency = 3.32, viewabilityPct = 72.8, bounceRatePct = 41.4,
    videoCompletionPct = 0.0, brandLiftPct = 2.0,
    creativeCount = 12, audienceSize = 9100000, bidStrategy = "tCPA",
    placementName = "Top of page" },
  { spendId = 5, campaignId = 1, channelId = 4, monthName = "Feb",
    spendUsd = 68000.0, revenueUsd = 96000.0, cpmUsd = 11.80, cpcUsd = 4.05,
    cpaUsd = 210.50, roas = 1.41,
    impressions = 5760000, clicks = 16790, conversions = 323, reachCount = 2410000,
    frequency = 2.39, viewabilityPct = 82.6, bounceRatePct = 39.0,
    videoCompletionPct = 61.3, brandLiftPct = 6.4,
    creativeCount = 4, audienceSize = 7600000, bidStrategy = "CPCV",
    placementName = "Pre-roll" },
  { spendId = 6, campaignId = 1, channelId = 2, monthName = "Mar",
    spendUsd = 47000.0, revenueUsd = 121000.0, cpmUsd = 4.20, cpcUsd = 0.91,
    cpaUsd = 58.90, roas = 2.57,
    impressions = 11190000, clicks = 51650, conversions = 798, reachCount = 3740000,
    frequency = 2.99, viewabilityPct = 65.0, bounceRatePct = 54.9,
    videoCompletionPct = 0.0, brandLiftPct = 3.3,
    creativeCount = 24, audienceSize = 14200000, bidStrategy = "Reach",
    placementName = "In-feed" },
  { spendId = 7, campaignId = 1, channelId = 5, monthName = "Mar",
    spendUsd = 14000.0, revenueUsd = 18000.0, cpmUsd = 18.40, cpcUsd = 0.0,
    cpaUsd = 0.0, roas = 1.29,
    impressions = 761000, clicks = 0, conversions = 0, reachCount = 402000,
    frequency = 1.89, viewabilityPct = 0.0, bounceRatePct = 0.0,
    videoCompletionPct = 0.0, brandLiftPct = 4.8,
    creativeCount = 2, audienceSize = 1900000, bidStrategy = "CPM",
    placementName = "Podcast midroll" },
  { spendId = 8, campaignId = 2, channelId = 1, monthName = "Jan",
    spendUsd = 33000.0, revenueUsd = 88000.0, cpmUsd = 5.80, cpcUsd = 1.61,
    cpaUsd = 44.90, roas = 2.67,
    impressions = 5690000, clicks = 20500, conversions = 735, reachCount = 2110000,
    frequency = 2.70, viewabilityPct = 69.9, bounceRatePct = 45.2,
    videoCompletionPct = 0.0, brandLiftPct = 1.2,
    creativeCount = 6, audienceSize = 4400000, bidStrategy = "tROAS",
    placementName = "Top of page" },
  { spendId = 9, campaignId = 2, channelId = 3, monthName = "Jan",
    spendUsd = 19000.0, revenueUsd = 26000.0, cpmUsd = 1.95, cpcUsd = 3.31,
    cpaUsd = 190.00, roas = 1.37,
    impressions = 9740000, clicks = 5740, conversions = 100, reachCount = 5100000,
    frequency = 1.91, viewabilityPct = 46.1, bounceRatePct = 71.3,
    videoCompletionPct = 0.0, brandLiftPct = 0.6,
    creativeCount = 5, audienceSize = 18000000, bidStrategy = "vCPM",
    placementName = "Sidebar" },
  { spendId = 10, campaignId = 2, channelId = 4, monthName = "Feb",
    spendUsd = 41000.0, revenueUsd = 63000.0, cpmUsd = 12.40, cpcUsd = 4.62,
    cpaUsd = 228.00, roas = 1.54,
    impressions = 3310000, clicks = 8870, conversions = 180, reachCount = 1490000,
    frequency = 2.22, viewabilityPct = 84.1, bounceRatePct = 36.7,
    videoCompletionPct = 64.9, brandLiftPct = 7.1,
    creativeCount = 3, audienceSize = 5200000, bidStrategy = "CPCV",
    placementName = "Pre-roll" },
  { spendId = 11, campaignId = 2, channelId = 1, monthName = "Mar",
    spendUsd = 36000.0, revenueUsd = 101000.0, cpmUsd = 5.95, cpcUsd = 1.55,
    cpaUsd = 42.10, roas = 2.81,
    impressions = 6050000, clicks = 23230, conversions = 855, reachCount = 2240000,
    frequency = 2.70, viewabilityPct = 70.6, bounceRatePct = 44.0,
    videoCompletionPct = 0.0, brandLiftPct = 1.4,
    creativeCount = 6, audienceSize = 4400000, bidStrategy = "tROAS",
    placementName = "Top of page" },
  { spendId = 12, campaignId = 2, channelId = 2, monthName = "Mar",
    spendUsd = 28000.0, revenueUsd = 59000.0, cpmUsd = 4.05, cpcUsd = 0.97,
    cpaUsd = 66.20, roas = 2.11,
    impressions = 6910000, clicks = 28870, conversions = 423, reachCount = 2380000,
    frequency = 2.90, viewabilityPct = 63.4, bounceRatePct = 56.6,
    videoCompletionPct = 0.0, brandLiftPct = 2.7,
    creativeCount = 14, audienceSize = 9800000, bidStrategy = "Reach",
    placementName = "In-feed" },
  { spendId = 13, campaignId = 2, channelId = 5, monthName = "Feb",
    spendUsd = 9000.0, revenueUsd = 11000.0, cpmUsd = 17.20, cpcUsd = 0.0,
    cpaUsd = 0.0, roas = 1.22,
    impressions = 523000, clicks = 0, conversions = 0, reachCount = 288000,
    frequency = 1.82, viewabilityPct = 0.0, bounceRatePct = 0.0,
    videoCompletionPct = 0.0, brandLiftPct = 3.9,
    creativeCount = 2, audienceSize = 1400000, bidStrategy = "CPM",
    placementName = "Podcast midroll" },
  { spendId = 14, campaignId = 1, channelId = 3, monthName = "Mar",
    spendUsd = 20000.0, revenueUsd = 37000.0, cpmUsd = 2.05, cpcUsd = 3.02,
    cpaUsd = 158.70, roas = 1.85,
    impressions = 9760000, clicks = 6620, conversions = 126, reachCount = 5540000,
    frequency = 1.76, viewabilityPct = 47.5, bounceRatePct = 69.1,
    videoCompletionPct = 0.0, brandLiftPct = 0.8,
    creativeCount = 8, audienceSize = 22000000, bidStrategy = "vCPM",
    placementName = "Sidebar" }
]

campaignDim = relation [
  { campaignId = 1, campaignName = "Spring range launch", objective = "Acquisition" },
  { campaignId = 2, campaignName = "Always-on retention", objective = "Retention" }
]

-- The channel VALUES are the names of the produced columns, which is what makes
-- the concise pivot spelling legal here.
channelDim = relation [
  { channelId = 1, channelName = "search"  },
  { channelId = 2, channelName = "social"  },
  { channelId = 3, channelName = "display" },
  { channelId = 4, channelName = "video"   },
  { channelId = 5, channelName = "audio"   }
]

-- Twenty-six columns after the joins.
media = spend ** campaignDim ** channelDim

-- ------------------------------------------------------------- the pivot
--
-- Narrow to identity + key + value, then transpose.  Five channels, three months
-- and two campaigns make thirty cells; the fact table has fourteen rows with
-- fourteen distinct (campaign, month, channel) triples, so SIXTEEN of the thirty
-- have no row behind them.  That is what the defaulted pivot is for.
byMonthChannel = groupBy {campaignName, monthName, channelName} (sumBy spendUsd) media

-- One line for the whole plan: the produced row IS the column list.
channelPlan        = pivotOnRow            {search, social, display, video, audio}
                                           spendUsd channelName
channelPlanDefault = pivotOnRowWithDefault {search, social, display, video, audio}
                                           spendUsd channelName

-- Missing cells are null.
spendByChannel        = pivotBy            channelPlan        byMonthChannel
-- Missing cells are zero, so the row can be summed across.
spendByChannelFilled  = pivotByWithDefault channelPlanDefault byMonthChannel

-- ------------------------------------------------------------- a leaderboard
--
-- Top two channels by spend within each month, on the long form.
topChannels = topNWithin {monthName} (desc spendUsd) 2 spendRank media

mediaReport = vflow [
  atomShown "## Media spend",
  atomShown "### By channel (missing cells null)",
  tabular Nothing spendByChannel,
  atomShown "### By channel (missing cells zero)",
  tabular Nothing spendByChannelFilled,
  atomShown "### Top two channels each month",
  tabular Nothing
    (topChannels # { monthName, campaignName, channelName, spendUsd, spendRank }),
  atomShown "### The long form",
  tabular Nothing
    (media # { campaignName, monthName, channelName, spendUsd, impressions,
               clicks, conversions, roas })
]
