module Present.SortShowcase where

{- ONE GRID, FOUR SORT STRATEGIES: the same sixteen-column league table drawn
   four times, changing nothing but how it is ordered, so the four mechanisms
   Ermine offers can be compared side by side.

   Fact: players (16 fields: playerId, playerName, teamName, divisionName,
         positionName, gamesPlayed, minutesPlayed, pointsScored, assistCount,
         reboundCount, turnoverCount, efficiency, salaryUsd, ageYears,
         contractYear, countryCode)

   WHY THIS FILE EXISTS. Ordering a report is where Ermine is least like SQL and
   most likely to surprise. There are FOUR different things called a sort, they
   live in different modules, and they compose in one direction only:

     1. `Relation.Sort.Sort r`      RELATIONAL order. Real, in the data, emitted
                                    as ORDER BY. `ordering`, `invert`, `only`,
                                    `reorder`, `limit`, `topK`, `bottomK`.
     2. `Layout.SortPriority`       the grid's INITIAL order, by display LABEL,
                                    with a priority number: `^ 0`, `^! 1`.
                                    Attached to a `Legend`, re-set by
                                    `reprioritizeLabel`.
     3. `Layout.SortStrategy r`     RELATIVE order. Read its module header
                                    twice: `sortBy reverse x` does NOT mean
                                    descending. It means "whatever order the
                                    thing that really sorts chooses, invert it
                                    for this column". It exists because a
                                    presentation may DISPLAY a column in an
                                    order that does not match the underlying
                                    values -- a month name, a grade letter, a
                                    reversed rank.
     4. `Ord {..k}`                 a comparison on the KEY RECORD, used by
                                    `softRelation` and `Layout.Column` when the
                                    column ORDER of a soft-schema grid has to be
                                    decided in Ermine rather than by the writer.

   The `Either (Sort k) (Ord {..k})` that `softRelation` and `DynamicFulcrum`
   both take is precisely the choice between (1) and (4): sort in the database,
   or sort in the report.

   SHAPES EXERCISED
     * `sortedBy` and `againstBy` from `Helpers.e`: `SortStrategy`'s `(++)` is a
       row PARTITION `t <- (r, s)`, so two strategies compose only if they name
       disjoint columns -- try to sort twice on one column and it does not check.
     * `hiddenBy`: a column that sorts but is not drawn (`Legend.exoticHidden`),
       whose legend row is the hidden column alone and must be `++`'d in.
     * `pinned` (`reprioritizeLabel`) moving one label's priority after the fact.
     * `Layout.Column`'s own `sortPriority` / `sortStrategy` / `formatSortedV`,
       which is the same machinery one level down.
     * `Relation.Sort`'s `ordering`, `invert`, `only`, `topK`, `bottomK`,
       `limit`, `recordOrd`.
     * `Ord.fromLess` building a record comparison for a soft grid's columns.

     >> :load core/examples/Present/Helpers.e
     >> :load core/examples/Present/SortShowcase.e
     >> sortingReport
     >> topScorers
     >> cheapestFive

   A REPL WARNING WORTH THE SPACE. This report was called `sortShowcase` until
   it hung a piped session for six minutes. `Console.other` decides whether a
   typed line is finished by asking, among other things, whether it CONTAINS the
   substring "case", "let" or "where" (`Console.scala:623`); "showcase" contains
   "case", so the REPL kept prompting `|>` for a continuation, and each empty
   read appended to a string it then re-scanned -- quadratic, and with stdin at
   EOF, unbounded. Any binding whose NAME contains one of those three substrings
   is unusable from a non-interactive `bin/ermine <file> < script`. Rename it,
   or drive it with `:type`.

   There is no `render`; evaluate the report and the relations. See
   `tracker/loopmodel/E4-EXAMPLES.md` gate G4.
-}

import Prelude
import Layout
import Layout.Format as Fmt
import Layout.Legend as Lg
import Layout.Presentation as Pres
import Layout.Column as Col
import Layout.Column.Unsafe as CU
import Layout.SortStrategy as SS
import Layout.SortPriority
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Sort as Sort
import Syntax.Relation
import Present.Helpers

field playerId, gamesPlayed, minutesPlayed, pointsScored : Int
field assistCount, reboundCount, turnoverCount, ageYears, contractYear : Int
field playerName, teamName, divisionName, positionName, countryCode : String
field efficiency, salaryUsd : Double

field pointsPerGame, salaryM : Double

-- ------------------------------------------------------------- the fact table

-- Sixteen columns, twelve players, four teams, two divisions.
players : [ playerId, playerName, teamName, divisionName, positionName
          , gamesPlayed, minutesPlayed, pointsScored, assistCount, reboundCount
          , turnoverCount, efficiency, salaryUsd, ageYears, contractYear
          , countryCode ]
players = relation [
  { playerId = 1, playerName = "A. Marchetti", teamName = "Harbour Kings", divisionName = "Eastern",
    positionName = "Guard", gamesPlayed = 74, minutesPlayed = 2610, pointsScored = 1489,
    assistCount = 412, reboundCount = 196, turnoverCount = 171, efficiency = 22.4,
    salaryUsd = 18400000.0, ageYears = 27, contractYear = 3, countryCode = "IT" },
  { playerId = 2, playerName = "B. Osei", teamName = "Harbour Kings", divisionName = "Eastern",
    positionName = "Forward", gamesPlayed = 78, minutesPlayed = 2740, pointsScored = 1322,
    assistCount = 181, reboundCount = 614, turnoverCount = 148, efficiency = 21.1,
    salaryUsd = 15200000.0, ageYears = 25, contractYear = 2, countryCode = "GH" },
  { playerId = 3, playerName = "C. Lindgren", teamName = "Harbour Kings", divisionName = "Eastern",
    positionName = "Centre", gamesPlayed = 69, minutesPlayed = 2180, pointsScored = 988,
    assistCount = 132, reboundCount = 702, turnoverCount = 131, efficiency = 19.8,
    salaryUsd = 9800000.0, ageYears = 31, contractYear = 5, countryCode = "SE" },
  { playerId = 4, playerName = "D. Reyes", teamName = "Northgate Foxes", divisionName = "Eastern",
    positionName = "Guard", gamesPlayed = 81, minutesPlayed = 2905, pointsScored = 1611,
    assistCount = 529, reboundCount = 204, turnoverCount = 203, efficiency = 24.0,
    salaryUsd = 21500000.0, ageYears = 24, contractYear = 1, countryCode = "MX" },
  { playerId = 5, playerName = "E. Kowalski", teamName = "Northgate Foxes", divisionName = "Eastern",
    positionName = "Forward", gamesPlayed = 76, minutesPlayed = 2410, pointsScored = 1104,
    assistCount = 224, reboundCount = 488, turnoverCount = 140, efficiency = 18.9,
    salaryUsd = 11300000.0, ageYears = 29, contractYear = 4, countryCode = "PL" },
  { playerId = 6, playerName = "F. Nakamura", teamName = "Northgate Foxes", divisionName = "Eastern",
    positionName = "Centre", gamesPlayed = 62, minutesPlayed = 1840, pointsScored = 742,
    assistCount = 101, reboundCount = 561, turnoverCount = 118, efficiency = 16.2,
    salaryUsd = 7400000.0, ageYears = 33, contractYear = 6, countryCode = "JP" },
  { playerId = 7, playerName = "G. Abioye", teamName = "Sandhill Wolves", divisionName = "Western",
    positionName = "Guard", gamesPlayed = 79, minutesPlayed = 2820, pointsScored = 1398,
    assistCount = 467, reboundCount = 221, turnoverCount = 188, efficiency = 22.0,
    salaryUsd = 17100000.0, ageYears = 26, contractYear = 2, countryCode = "NG" },
  { playerId = 8, playerName = "H. Petrov", teamName = "Sandhill Wolves", divisionName = "Western",
    positionName = "Forward", gamesPlayed = 72, minutesPlayed = 2350, pointsScored = 1178,
    assistCount = 198, reboundCount = 542, turnoverCount = 151, efficiency = 19.4,
    salaryUsd = 12600000.0, ageYears = 28, contractYear = 3, countryCode = "BG" },
  { playerId = 9, playerName = "I. Duarte", teamName = "Sandhill Wolves", divisionName = "Western",
    positionName = "Centre", gamesPlayed = 65, minutesPlayed = 1990, pointsScored = 856,
    assistCount = 118, reboundCount = 633, turnoverCount = 124, efficiency = 17.6,
    salaryUsd = 8900000.0, ageYears = 30, contractYear = 4, countryCode = "BR" },
  { playerId = 10, playerName = "J. Whitfield", teamName = "Cedar Rapids", divisionName = "Western",
    positionName = "Guard", gamesPlayed = 83, minutesPlayed = 3010, pointsScored = 1702,
    assistCount = 551, reboundCount = 238, turnoverCount = 214, efficiency = 25.3,
    salaryUsd = 23900000.0, ageYears = 23, contractYear = 1, countryCode = "US" },
  { playerId = 11, playerName = "K. Haddad", teamName = "Cedar Rapids", divisionName = "Western",
    positionName = "Forward", gamesPlayed = 70, minutesPlayed = 2260, pointsScored = 1041,
    assistCount = 209, reboundCount = 471, turnoverCount = 137, efficiency = 18.1,
    salaryUsd = 10800000.0, ageYears = 32, contractYear = 5, countryCode = "LB" },
  { playerId = 12, playerName = "L. Fitzgerald", teamName = "Cedar Rapids", divisionName = "Western",
    positionName = "Centre", gamesPlayed = 58, minutesPlayed = 1720, pointsScored = 690,
    assistCount = 94, reboundCount = 522, turnoverCount = 109, efficiency = 15.4,
    salaryUsd = 6700000.0, ageYears = 34, contractYear = 6, countryCode = "IE" }]

-- Two derived measures, so there is something to sort on that is not in the
-- fact table. `fromNumericOp` is the numeric widening: both operands are `Int`
-- columns and the quotient is wanted as a `Double`, and Ermine will not coerce
-- silently -- `Op` arithmetic is homogeneous in its numeric type.
enriched =
     players
  |> combine_Op (fromNumericOp_Op pointsScored /_Op fromNumericOp_Op gamesPlayed)
                pointsPerGame
  |> combine_Op (scaledBy 1000000.0 salaryUsd) salaryM

shown = enriched # { playerName, teamName, divisionName, positionName
                   , gamesPlayed, pointsScored, pointsPerGame, assistCount
                   , reboundCount, efficiency, salaryM, ageYears }

-- ================================================ 1. relational order (Sort r)

-- REAL order, in the data. `ordering` builds it from a row; `invert` flips every
-- column of it at once; `only` narrows an existing sort to a sub-row. This is
-- the sort that reaches the database as ORDER BY -- see
-- `Present/WriterOutputs.e`, where `dumpQueryInOrder` emits exactly this.
byPoints    = ordering_Sort { pointsScored }
byPointsDesc = invert_Sort byPoints

-- `topK` / `bottomK` are `limit` with the sort built in: the row says what to
-- sort on and the Int how many to keep.
topScorers  = topK_Sort { pointsScored } 5 enriched
cheapestFive = bottomK_Sort { salaryUsd } 5 enriched

-- `limit` is the general form: a sort, an offset and a count.
secondPage = limit_Sort (ordering_Sort { salaryUsd }) (Just 4) (Just 4) enriched

-- ==================================================== 2. the grid's INITIAL order

-- Priority numbers on the LABELS, not the columns. `^ n` is ascending at
-- priority n, `^! n` descending; `Unsorted` (the default, and what `unsorted`
-- gives) means the column takes no part. Lower number wins.
--
-- This is what the writer uses to decide which column the arrow starts on.
priorityLegend : Legend_Lg (| playerName, teamName, divisionName, positionName
                             , gamesPlayed, pointsScored, pointsPerGame
                             , assistCount, reboundCount, efficiency, salaryM
                             , ageYears |)
priorityLegend =
  withFormats ([ (divisionName, "Division") ^ 0     -- primary,   ascending
               , (teamName,     "Team")     ^ 1     -- secondary, ascending
               , (playerName,   "Player")   ^ 2
               , unsorted (positionName, "Position") ]_Sorted_Lg)
              (round_Fmt 1)
              { gamesPlayed, pointsScored, pointsPerGame, assistCount
              , reboundCount, efficiency, salaryM, ageYears }

byPriority = tabular_K ([tabLegend_O := priorityLegend]_Opt) shown

-- The SAME legend with one label moved to the front, descending. Nothing is
-- rebuilt: `pinned` is `reprioritizeLabel`, which rewrites one entry of the
-- label/priority list and leaves the presentations alone.
byEfficiency =
  tabular_K ([tabLegend_O := pinned "Player" Unsorted
                               (pinned "Division" (descending 5) priorityLegend)]_Opt)
            shown

-- ============================================== 3. RELATIVE order (SortStrategy)

-- A strategy over two columns, composed by `Layout.SortStrategy.(++)` -- whose
-- partition `t <- (r, s)` is the whole content of the combinator. `sortedBy`
-- names the direction of each half.
--
-- `forward` means "as the underlying data says"; `reverse` means "the opposite
-- of whatever the real sort chose for this column". Neither means ascending or
-- descending on its own, which is why the module's own header spends twenty
-- lines saying so.
nameThenSalary : SortStrategy_SS (| playerName, salaryM |)
nameThenSalary = sortedBy forward_SS playerName reverse_SS (round_Pres 1 salaryM)

salaryAgainst : SortStrategy_SS (| salaryM |)
salaryAgainst = againstBy (round_Pres 1 salaryM)

-- The strategy is attached to a column through `exoticLegend`, which is what
-- `Layout.Legend.legend` calls with `sortBy forward` as its default. Here the
-- default is replaced.
strategyLegend : Legend_Lg (| playerName, teamName, salaryM, pointsPerGame |)
strategyLegend =
  ( labelled playerName                     "Player"
  . labelled teamName                       "Team" )
  (exoticLegend_Lg (round_Pres 1 salaryM) salaryAgainst (descending 0) "Salary $m"
     ++_Lg legend_Lg (round_Pres 1 pointsPerGame) "Points per game")

byStrategy =
  tabular_K ([tabLegend_O := strategyLegend]_Opt)
            (shown # { playerName, teamName, salaryM, pointsPerGame })

-- ================================================ 4. a HIDDEN sort column

-- Sort by a column the reader never sees. `hiddenBy` is
-- `Legend.exoticHidden`, whose legend carries the column's ROW but draws
-- nothing; `(++)`'s partition is what forces the hidden column to be in the
-- relation, so this cannot silently sort on a column that is not there.
--
-- The classic use: display a formatted grade, order by the numeric rank behind
-- it. Here: show the player and the team, order by minutes played.
hiddenSortLegend : Legend_Lg (| playerName, teamName, pointsPerGame, minutesPlayed |)
hiddenSortLegend =
  ( labelled playerName                    "Player"
  . labelled teamName                      "Team"
  . labelled (round_Pres 1 pointsPerGame)  "Points per game" )
  (hiddenBy minutesPlayed (descending 0))

byHidden =
  tabular_K ([tabLegend_O := hiddenSortLegend]_Opt)
            (enriched # { playerName, teamName, pointsPerGame, minutesPlayed })

-- ======================================== 5. the same machinery in Layout.Column

-- `Layout.Column` is the layer under `tabular`: a column at a time, with the
-- heading, the presentation, the sort priority and the sort strategy each set
-- by their own combinator. `columnTable` draws the result.
--
-- `Column`'s phantom `(name, legend, presentation, drilldown)` tuple is what
-- makes the ORDER of these calls checkable: `formatV` demands `Unbound`, so a
-- presentation cannot be set twice (that is `reformatV`), and `keys` demands
-- the legend slot be unbound.
salaryColumn =
  column_Col (enriched # { teamName, playerName, salaryM })
    |> heading_Col (val "Salary $m")
    |> formatSortedV_Col (round_Pres 1 salaryM) salaryAgainst
    |> sortPriority_Col (descending 0)
    |> keys_Col { teamName, playerName }

byColumnApi = columnTable salaryColumn

-- ONE LAYER FURTHER DOWN. `Layout.Column.Unsafe` is the seam between the
-- `Layout.Column` tree above and the writer: `column#` boxes it into the
-- writer's `Table#`, which is literally what `columnTable` does on the line
-- before (`columnTable col = Report $ w -> columnTableW w (column# col)`).
-- Its module header says "you only care about `column#`", and this is the
-- only place in `core/examples` that names it -- it is here so a reader who
-- goes looking for where a `Column` stops being Ermine finds the line.
boxedTable = column#_CU salaryColumn

-- =============================================== 6. an Ord on the key RECORD

-- The fourth kind. `Ord.fromLess` builds a comparison from a less-than test on
-- the key RECORD, which is what a soft-schema grid needs when the column order
-- is not the natural order of the key values -- position, here, which sorts
-- Guard / Forward / Centre and not alphabetically.
positionRank p = if (p == "Guard") 0 (if (p == "Forward") 1 2)

byPositionRank = fromLess (a b -> positionRank (a ! positionName) <
                                  positionRank (b ! positionName))

-- `softRelation`'s second argument is `Either (Sort k) (Ord {..k})`: the LEFT is
-- kind (1), sorted in the data; the RIGHT is kind (4), sorted here. This grid
-- takes the right.
positionGrid =
  keyValueTabular
    (softRelation positionName (Right byPositionRank)
                  (_ -> unsorted (round_Pres 1 pointsPerGame, Nothing)))
    (Just (legendFor { playerName, teamName }))
    (enriched # { playerName, teamName, positionName, pointsPerGame })

-- `recordOrd` is the other direction: a `Sort` turned into an `Ord`, so a
-- relational sort can be reused where a record comparison is wanted.
byPointsRecordOrd : Ord (Record (| pointsScored |))
byPointsRecordOrd = recordOrd_Sort byPointsDesc

-- ==================================================================== the page

sortingReport = vflow [
  h2 "One table, four ways to order it",
  h3 "1. Legend priorities: division, then team, then player",
  byPriority,
  h3 "2. The same legend, one label re-prioritised to descending",
  byEfficiency,
  h3 "3. A SortStrategy: salary displayed against the grid's own order",
  byStrategy,
  h3 "4. A hidden sort column: ordered by minutes, which is not shown",
  byHidden,
  h3 "5. The same, one column at a time, through Layout.Column",
  byColumnApi,
  h3 "6. A soft grid whose COLUMN order comes from an Ord on the key record",
  positionGrid,
  vstrut,
  h3 "Relational order: top five scorers",
  tabular Nothing (topScorers # { playerName, teamName, pointsScored }),
  h3 "Relational order: five cheapest",
  tabular Nothing (cheapestFive # { playerName, teamName, salaryM }),
  h3 "Relational order: the second page by salary",
  tabular Nothing (secondPage # { playerName, salaryM })
]
