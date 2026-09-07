module Wide.Leaderboard where

{- SEASON LEADERBOARD for a professional esports league, over a THIRTY-COLUMN
   player-season fact table.

   The point of the example is that not one of the five leaderboard columns
   names the other twenty-nine.  `rankWithin {division} (desc kills) killRank`
   says "rank by kills inside each division"; the row variable in the helper's
   signature carries damage, salary, sponsorship, follower counts and the rest
   through untouched.  Adding a thirty-first measure to `playerSeason` below
   changes nothing in the report.

   Fact:       playerSeason (30 columns)
                 keys      playerId, teamId
                 volume    gamesPlayed, minutesPlayed, roundsWon, roundsLost
                 combat    kills, deaths, assists, damageDealt, damageTaken,
                           healingDone, firstBloods, aces, clutches
                 skill     headshotPct, accuracyPct, utilityScore,
                           economyRating, objectivesTaken
                 honours   mvpAwards, penalties, fanVotes
                 money     prizeUsd, salaryUsd, sponsorUsd, travelUsd
                 presence  bootcampDays, streamHours, followers
   Dimensions: player   (playerId -> handle, fullName, country, roleName)
               team     (teamId   -> teamName, division, coach, homeCity)

   Helpers used: rankWithin, denseWithin, rowNumberWithin, nTileWithin,
                 topNWithin, asc, desc, thenBy (all from Wide.Helpers).

   Solver shapes exercised:
     * five window solves over a 38-column joined row, each minting the window
       row `w <- (k, s)` and the remainder `r <- (w, o)`.  Before this directory
       existed, `Relation.Windowed` had NO caller anywhere in `core/examples`, so
       that pair had never been solved by an example at all;
     * `topNWithin`, whose extra `t <- (c, u)` re-partitions a row the SAME
       helper call just minted, so the two constraints overlap on `c`;
     * a two-column sort (`thenBy`), which makes the window row `w` a union of
       three rows rather than two.

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/Leaderboard.e
     >> killLeaders
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field playerId, teamId : Int
field gamesPlayed : Int
field minutesPlayed, roundsWon, roundsLost : Double
field kills, deaths, assists, damageDealt, damageTaken, healingDone : Double
field firstBloods, aces, clutches : Double
field headshotPct, accuracyPct, utilityScore, economyRating, objectivesTaken : Double
field mvpAwards, penalties, fanVotes : Double
field prizeUsd, salaryUsd, sponsorUsd, travelUsd : Double
field bootcampDays, streamHours, followers : Double
field handle, fullName, country, roleName : String
field teamName, division, coach, homeCity : String
field killRank, mvpRank, payRank, economyQuartile, damageRank : Int
field kdRatio : Double

-- Thirty columns.  Nine rows: enough to make the ranks interesting inside each
-- of the two divisions, small enough to read.
playerSeason = relation [
  { playerId = 1, teamId = 10, gamesPlayed = 42, minutesPlayed = 2510.0,
    roundsWon = 611.0, roundsLost = 508.0,
    kills = 1204.0, deaths = 881.0, assists = 402.0,
    damageDealt = 168400.0, damageTaken = 141200.0, healingDone = 4100.0,
    firstBloods = 142.0, aces = 9.0, clutches = 31.0,
    headshotPct = 41.2, accuracyPct = 23.8, utilityScore = 78.4,
    economyRating = 91.0, objectivesTaken = 88.0,
    mvpAwards = 11.0, penalties = 1.0, fanVotes = 41200.0,
    prizeUsd = 84000.0, salaryUsd = 180000.0, sponsorUsd = 46000.0, travelUsd = 21500.0,
    bootcampDays = 62.0, streamHours = 310.0, followers = 812000.0 },
  { playerId = 2, teamId = 10, gamesPlayed = 42, minutesPlayed = 2488.0,
    roundsWon = 611.0, roundsLost = 508.0,
    kills = 1041.0, deaths = 902.0, assists = 611.0,
    damageDealt = 151900.0, damageTaken = 148800.0, healingDone = 12800.0,
    firstBloods = 88.0, aces = 4.0, clutches = 22.0,
    headshotPct = 33.9, accuracyPct = 25.1, utilityScore = 91.6,
    economyRating = 88.0, objectivesTaken = 141.0,
    mvpAwards = 6.0, penalties = 0.0, fanVotes = 28700.0,
    prizeUsd = 84000.0, salaryUsd = 150000.0, sponsorUsd = 22000.0, travelUsd = 21500.0,
    bootcampDays = 62.0, streamHours = 96.0, followers = 244000.0 },
  { playerId = 3, teamId = 11, gamesPlayed = 40, minutesPlayed = 2402.0,
    roundsWon = 548.0, roundsLost = 561.0,
    kills = 1188.0, deaths = 940.0, assists = 380.0,
    damageDealt = 172100.0, damageTaken = 158900.0, healingDone = 2600.0,
    firstBloods = 151.0, aces = 12.0, clutches = 27.0,
    headshotPct = 44.8, accuracyPct = 22.4, utilityScore = 64.1,
    economyRating = 79.0, objectivesTaken = 71.0,
    mvpAwards = 9.0, penalties = 3.0, fanVotes = 51900.0,
    prizeUsd = 41000.0, salaryUsd = 165000.0, sponsorUsd = 61000.0, travelUsd = 19800.0,
    bootcampDays = 48.0, streamHours = 512.0, followers = 1340000.0 },
  { playerId = 4, teamId = 11, gamesPlayed = 40, minutesPlayed = 2380.0,
    roundsWon = 548.0, roundsLost = 561.0,
    kills = 903.0, deaths = 966.0, assists = 588.0,
    damageDealt = 133700.0, damageTaken = 161400.0, healingDone = 15400.0,
    firstBloods = 61.0, aces = 2.0, clutches = 18.0,
    headshotPct = 29.7, accuracyPct = 26.0, utilityScore = 97.2,
    economyRating = 84.0, objectivesTaken = 158.0,
    mvpAwards = 4.0, penalties = 1.0, fanVotes = 19400.0,
    prizeUsd = 41000.0, salaryUsd = 128000.0, sponsorUsd = 14000.0, travelUsd = 19800.0,
    bootcampDays = 48.0, streamHours = 41.0, followers = 96000.0 },
  { playerId = 5, teamId = 12, gamesPlayed = 41, minutesPlayed = 2455.0,
    roundsWon = 592.0, roundsLost = 530.0,
    kills = 1120.0, deaths = 851.0, assists = 447.0,
    damageDealt = 159300.0, damageTaken = 138600.0, healingDone = 5200.0,
    firstBloods = 118.0, aces = 7.0, clutches = 35.0,
    headshotPct = 38.4, accuracyPct = 24.6, utilityScore = 81.0,
    economyRating = 96.0, objectivesTaken = 102.0,
    mvpAwards = 13.0, penalties = 0.0, fanVotes = 63100.0,
    prizeUsd = 122000.0, salaryUsd = 210000.0, sponsorUsd = 88000.0, travelUsd = 24100.0,
    bootcampDays = 71.0, streamHours = 188.0, followers = 604000.0 },
  { playerId = 6, teamId = 20, gamesPlayed = 39, minutesPlayed = 2311.0,
    roundsWon = 501.0, roundsLost = 546.0,
    kills = 981.0, deaths = 908.0, assists = 512.0,
    damageDealt = 141800.0, damageTaken = 149100.0, healingDone = 9100.0,
    firstBloods = 97.0, aces = 5.0, clutches = 24.0,
    headshotPct = 36.1, accuracyPct = 24.0, utilityScore = 86.3,
    economyRating = 74.0, objectivesTaken = 119.0,
    mvpAwards = 5.0, penalties = 2.0, fanVotes = 22800.0,
    prizeUsd = 28000.0, salaryUsd = 121000.0, sponsorUsd = 9000.0, travelUsd = 26400.0,
    bootcampDays = 39.0, streamHours = 264.0, followers = 318000.0 },
  { playerId = 7, teamId = 20, gamesPlayed = 39, minutesPlayed = 2298.0,
    roundsWon = 501.0, roundsLost = 546.0,
    kills = 1096.0, deaths = 872.0, assists = 341.0,
    damageDealt = 156200.0, damageTaken = 143700.0, healingDone = 1900.0,
    firstBloods = 133.0, aces = 8.0, clutches = 29.0,
    headshotPct = 43.5, accuracyPct = 21.9, utilityScore = 59.8,
    economyRating = 82.0, objectivesTaken = 64.0,
    mvpAwards = 8.0, penalties = 4.0, fanVotes = 37600.0,
    prizeUsd = 28000.0, salaryUsd = 143000.0, sponsorUsd = 31000.0, travelUsd = 26400.0,
    bootcampDays = 39.0, streamHours = 402.0, followers = 727000.0 },
  { playerId = 8, teamId = 21, gamesPlayed = 38, minutesPlayed = 2244.0,
    roundsWon = 462.0, roundsLost = 588.0,
    kills = 842.0, deaths = 1011.0, assists = 604.0,
    damageDealt = 124500.0, damageTaken = 170200.0, healingDone = 18800.0,
    firstBloods = 54.0, aces = 1.0, clutches = 14.0,
    headshotPct = 27.4, accuracyPct = 26.8, utilityScore = 99.1,
    economyRating = 68.0, objectivesTaken = 171.0,
    mvpAwards = 2.0, penalties = 0.0, fanVotes = 11900.0,
    prizeUsd = 12000.0, salaryUsd = 98000.0, sponsorUsd = 5000.0, travelUsd = 22900.0,
    bootcampDays = 31.0, streamHours = 58.0, followers = 74000.0 },
  { playerId = 9, teamId = 21, gamesPlayed = 38, minutesPlayed = 2260.0,
    roundsWon = 462.0, roundsLost = 588.0,
    kills = 1009.0, deaths = 974.0, assists = 398.0,
    damageDealt = 147600.0, damageTaken = 166300.0, healingDone = 3300.0,
    firstBloods = 104.0, aces = 6.0, clutches = 20.0,
    headshotPct = 39.6, accuracyPct = 23.2, utilityScore = 72.5,
    economyRating = 77.0, objectivesTaken = 93.0,
    mvpAwards = 3.0, penalties = 1.0, fanVotes = 16400.0,
    prizeUsd = 12000.0, salaryUsd = 110000.0, sponsorUsd = 12000.0, travelUsd = 22900.0,
    bootcampDays = 31.0, streamHours = 147.0, followers = 189000.0 }
]

playerDim = relation [
  { playerId = 1, handle = "vex",     fullName = "Vera Okonkwo",   country = "NG", roleName = "Duelist"  },
  { playerId = 2, handle = "sable",   fullName = "Sabine Roche",   country = "FR", roleName = "Support"  },
  { playerId = 3, handle = "kite",    fullName = "Kit Andersen",   country = "DK", roleName = "Duelist"  },
  { playerId = 4, handle = "orrin",   fullName = "Orrin Baptiste", country = "CA", roleName = "Support"  },
  { playerId = 5, handle = "nova",    fullName = "Nova Petrova",   country = "BG", roleName = "Flex"     },
  { playerId = 6, handle = "tessel",  fullName = "Tessa Lindqvist",country = "SE", roleName = "Support"  },
  { playerId = 7, handle = "rax",     fullName = "Rakesh Menon",   country = "IN", roleName = "Duelist"  },
  { playerId = 8, handle = "quill",   fullName = "Quinn Alvarez",  country = "MX", roleName = "Support"  },
  { playerId = 9, handle = "brant",   fullName = "Brant Ihara",    country = "JP", roleName = "Flex"     }
]

teamDim = relation [
  { teamId = 10, teamName = "Meridian",   division = "North", coach = "H. Sowande",  homeCity = "Toronto"   },
  { teamId = 11, teamName = "Halcyon",    division = "North", coach = "P. Nyman",    homeCity = "Oslo"      },
  { teamId = 12, teamName = "Aurora",     division = "North", coach = "L. Marchetti",homeCity = "Montreal"  },
  { teamId = 20, teamName = "Coriolis",   division = "South", coach = "D. Okafor",   homeCity = "Sao Paulo" },
  { teamId = 21, teamName = "Vantage",    division = "South", coach = "M. Ferreira", homeCity = "Lisbon"    }
]

-- 38 columns after the two joins: the row the window helpers carry.
season = playerSeason ** playerDim ** teamDim

-- Five leaderboard columns, five window solves.  Each names two columns.
killLeaders    = rankWithin      {division} (desc kills)         killRank        season
mvpLeaders     = denseWithin     {division} (desc mvpAwards)     mvpRank         season
payOrder       = rowNumberWithin {teamId}   (desc prizeUsd ` thenBy ' asc handle)
                                                                 payRank         season
economyTiles   = nTileWithin     {division} (desc economyRating) 4
                                                                 economyQuartile season
damagePodium   = topNWithin      {division} (desc damageDealt)   3 damageRank    season

-- One ordinary derived column, for contrast: no window, no partition.
withKd = combine_Op (col_Op kills /_Op col_Op deaths) kdRatio season

leaderboardReport = vflow [
  atomShown "## Season leaderboard",
  atomShown "### Kill rank within division",
  tabular Nothing (killLeaders # {division, handle, teamName, kills, killRank}),
  atomShown "### Top three by damage, per division",
  tabular Nothing (damagePodium # {division, handle, damageDealt, damageRank}),
  atomShown "### Economy quartile within division",
  tabular Nothing (economyTiles # {division, handle, economyRating, economyQuartile})
]
