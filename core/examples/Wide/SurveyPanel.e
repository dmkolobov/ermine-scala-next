module Wide.SurveyPanel where

{- THE ROUND TRIP: a wide survey table melted into key/value rows and pivoted
   back into a wide table again.

   Survey data arrives wide -- one row per respondent, one column per question --
   and has to be narrow to be analysed, because "the mean score by question and
   country" cannot be written over a table whose questions are columns.  Then it
   has to be wide again to be read.  `melt4` does the first move and `pivotBy`
   the second, and between them sits an ordinary aggregation that neither knows
   nor cares how many questions there were.

   The interesting part is that the two directions are NOT symmetric in the type
   system.  `melt4` has a two-constraint signature a person can read
   (`r <- (i, fa, fb, fc, fd)`, `out <- (i, key, val)`); `pivotBy` has
   `r <- (k, v, i)` and `s <- (i, p)` and mints the identity row `i` itself.  A
   melt names the columns it is collapsing.  A pivot names the columns it is
   creating.  Both are fixed arity, and section 7 of
   `tracker/loopmodel/E1-EXAMPLES.md` says why neither can be otherwise.

   Fact:       response (20 columns)
                 keys      responseId, respondentId, waveId
                 scores    scoreSpeed, scorePrice, scoreSupport, scoreQuality
                 profile   ageBand, countryCode, industryName, employerSize,
                           seniority, tenureYears, purchaseRole
                 meta      submittedDay, channelName, durationSec,
                           completionPct, deviceKind, languageCode
   Dimensions: wave (waveId -> waveName, fieldworkStart, fieldworkEnd)

   Helpers used: melt4, startPivot, pivotColumn, pivotBy (Wide.Helpers).

   Solver shapes exercised:
     * `melt4` at a call site -- four `except`s, four `combine`s, four `rename`s
       and three `union`s, all reconciled against a TWO-constraint signature.
       Inferred rather than annotated, the three-column `melt3` publishes 22 row
       constraints over 19 existentials instead of 2 over 1 (measured; section 5
       of the E1 report) -- the annotation is what keeps the call site cheap;
     * a pivot whose input is the OUTPUT of a melt, so the pivot's existential
       identity row `i` is itself a row the melt minted -- one generative helper
       feeding another, which no other module here does;
     * `groupBy` between the two, over the melted key.

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/SurveyPanel.e
     >> :type meltedScores
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field responseId, respondentId, waveId : Int
field employerSize, tenureYears, durationSec : Int
field scoreSpeed, scorePrice, scoreSupport, scoreQuality : Double
field completionPct : Double
field ageBand, countryCode, industryName, seniority, purchaseRole : String
field channelName, deviceKind, languageCode : String
field submittedDay : Date
field waveName : String
field fieldworkStart, fieldworkEnd : Date
field questionKey : String
field questionScore : Double
field speed, price, support, quality : Double

-- Twenty columns.  Six respondents, four scored questions each.
response = relation [
  { responseId = 1, respondentId = 8001, waveId = 1,
    scoreSpeed = 4.0, scorePrice = 2.0, scoreSupport = 5.0, scoreQuality = 4.0,
    ageBand = "35-44", countryCode = "DE", industryName = "Manufacturing",
    employerSize = 4200, seniority = "Director", tenureYears = 6,
    purchaseRole = "Decider",
    submittedDay = yyyymmdd 2025 4 2, channelName = "Email", durationSec = 412,
    completionPct = 100.0, deviceKind = "Desktop", languageCode = "de" },
  { responseId = 2, respondentId = 8002, waveId = 1,
    scoreSpeed = 3.0, scorePrice = 4.0, scoreSupport = 3.0, scoreQuality = 5.0,
    ageBand = "25-34", countryCode = "DE", industryName = "Software",
    employerSize = 310, seniority = "Manager", tenureYears = 2,
    purchaseRole = "Influencer",
    submittedDay = yyyymmdd 2025 4 3, channelName = "Email", durationSec = 288,
    completionPct = 100.0, deviceKind = "Mobile", languageCode = "de" },
  { responseId = 3, respondentId = 8003, waveId = 1,
    scoreSpeed = 5.0, scorePrice = 1.0, scoreSupport = 4.0, scoreQuality = 4.0,
    ageBand = "45-54", countryCode = "BR", industryName = "Retail",
    employerSize = 15800, seniority = "VP", tenureYears = 11,
    purchaseRole = "Decider",
    submittedDay = yyyymmdd 2025 4 4, channelName = "Panel", durationSec = 655,
    completionPct = 100.0, deviceKind = "Desktop", languageCode = "pt" },
  { responseId = 4, respondentId = 8004, waveId = 2,
    scoreSpeed = 2.0, scorePrice = 5.0, scoreSupport = 2.0, scoreQuality = 3.0,
    ageBand = "25-34", countryCode = "BR", industryName = "Software",
    employerSize = 90, seniority = "Individual", tenureYears = 1,
    purchaseRole = "User",
    submittedDay = yyyymmdd 2025 10 1, channelName = "Panel", durationSec = 197,
    completionPct = 92.0, deviceKind = "Mobile", languageCode = "pt" },
  { responseId = 5, respondentId = 8005, waveId = 2,
    scoreSpeed = 4.0, scorePrice = 3.0, scoreSupport = 5.0, scoreQuality = 5.0,
    ageBand = "35-44", countryCode = "JP", industryName = "Manufacturing",
    employerSize = 27400, seniority = "Manager", tenureYears = 8,
    purchaseRole = "Influencer",
    submittedDay = yyyymmdd 2025 10 2, channelName = "Email", durationSec = 501,
    completionPct = 100.0, deviceKind = "Desktop", languageCode = "ja" },
  { responseId = 6, respondentId = 8006, waveId = 2,
    scoreSpeed = 3.0, scorePrice = 2.0, scoreSupport = 4.0, scoreQuality = 2.0,
    ageBand = "55-64", countryCode = "JP", industryName = "Retail",
    employerSize = 640, seniority = "Director", tenureYears = 14,
    purchaseRole = "Decider",
    submittedDay = yyyymmdd 2025 10 5, channelName = "Phone", durationSec = 738,
    completionPct = 100.0, deviceKind = "Desktop", languageCode = "ja" }
]

waveDim = relation [
  { waveId = 1, waveName = "2025 H1",
    fieldworkStart = yyyymmdd 2025 4 1, fieldworkEnd = yyyymmdd 2025 4 30 },
  { waveId = 2, waveName = "2025 H2",
    fieldworkStart = yyyymmdd 2025 10 1, fieldworkEnd = yyyymmdd 2025 10 31 }
]

-- --------------------------------------------------------------- melt (long)
--
-- `melt4`'s `r <- (i, fa, fb, fc, fd)` says the input row is exactly the identity
-- plus the four measures, so the input has to be projected -- but the identity is
-- as wide as you want it, and every column you keep is a column you can then
-- analyse BY.  Keeping the four profile columns is what makes the mean score by
-- question and by COUNTRY writable below; they are repeated on all four output
-- rows, which is precisely what the identity row `i` is for.  What has to go is
-- only the metadata nobody groups by.
scored = response # { respondentId, waveId, countryCode, industryName,
                      seniority, ageBand,
                      scoreSpeed, scorePrice, scoreSupport, scoreQuality }

meltedScores =
  melt4 questionKey questionScore scoreSpeed scorePrice scoreSupport scoreQuality scored

-- Now the analysis that could not be written over the wide form: mean score per
-- question per wave, over however many questions there turn out to be.
meanByQuestion =
  groupBy {waveId, questionKey} (meanBy questionScore) meltedScores

-- And the analysis the wide form could not express at all, now that the profile
-- columns survived the melt: the mean score for each question in each country.
meanByCountry =
  groupBy {countryCode, questionKey} (meanBy questionScore) meltedScores

-- Named waves, for the report.
meanByWave = meanByQuestion ** toMem waveDim

-- ------------------------------------------------------- pivot back (wide)
--
-- And back again, with the four question keys becoming four columns.  Note that
-- the pivot names the OUTPUT columns and the melt named the INPUT ones: the
-- round trip is spelled out twice, once in each direction, and neither
-- direction can be written generically over "however many there are".
questionFulcrum =
  pivotColumn quality "scoreQuality" questionKey questionScore
    (pivotColumn support "scoreSupport" questionKey questionScore
      (pivotColumn price "scorePrice" questionKey questionScore
        (pivotColumn speed "scoreSpeed" questionKey questionScore
          (startPivot questionKey questionScore))))

meanWide = pivotBy questionFulcrum meanByQuestion

surveyReport = vflow [
  atomShown "## Customer satisfaction panel",
  atomShown "### Long form: one row per respondent per question",
  tabular Nothing meltedScores,
  atomShown "### Mean score by wave and question",
  tabular Nothing (meanByWave # { waveName, questionKey, questionScore }),
  atomShown "### Mean score by country and question",
  tabular Nothing meanByCountry,
  atomShown "### Back to wide: one row per wave",
  tabular Nothing meanWide,
  atomShown "### The panel",
  tabular Nothing
    (response # { respondentId, countryCode, industryName, seniority, completionPct })
]
