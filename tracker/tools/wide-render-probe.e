module RenderProbe where

{- E1.6: the nearest thing to `render` this repository has.

   There is no Writer in ermine-scala, so a `Report` cannot be run.  What CAN be
   done is compile each report's underlying relation to SQL through the shipped
   scanners and execute it, which exercises the whole relational pipeline --
   pivot, window, join, group -- and produces a real table.

   `sqlite`  : runnable as-is, but has no OVER clause (emits a TODO stub).
   `sqlServer`: emits real OVER clauses; the literal syntax needs rewriting for
                sqlite (tracker/tools/tsql2sqlite.py).

   The matching `.in` file precedes every binding name with the string literal
   `"@@<name>"`, so `sql-render.sh` pairs a name with the answer that follows it
   rather than counting positions.  Add a binding here AND its two lines there. -}

import Prelude
import Scanners
import Internal.SMEnv
import IO.Unsafe
import Native.Record
import Relation.Predicate as Pred
import Syntax.Relation

import Wide.Leaderboard as Lb
import Wide.SalesLedger as Sl
import Wide.TrialBalance as Tb
import Wide.RevenueShare as Rs
import Wide.SurveyPanel as Sp
import Wide.WardRoster as Wr
import Wide.BranchDeposits as Bd
import Wide.MediaSpend as Ms
import Wide.ClaimsExperience as Ce

field q : Int

lite = sqlite cachedSMEnv
mss  = sqlServer cachedSMEnv

dumpL r = unsafePerformIO (dumpQuery lite r)
dumpM r = unsafePerformIO (dumpQuery mss r)

-- Non-window relations: sqlite SQL, executable as it stands.
q_survey_melt   = dumpL meltedScores_Sp
q_survey_mean   = dumpL meanByQuestion_Sp
q_branch_spread = dumpL withSpread_Bd
q_branch_usd    = dumpL withUsd_Bd
q_claims_ratios = dumpL claimsWithRatios_Ce
q_sales_group   = dumpL byCustomerQuarter_Sl
q_sales_line    = dumpL byCustomerLine_Sl
q_media_group   = dumpL byMonthChannel_Ms
q_ward_join     = dumpL roster_Wr

-- Window relations: MS SQL SQL, real OVER clauses.
q_leader_rank   = dumpM killLeaders_Lb
q_leader_tile   = dumpM economyTiles_Lb
q_leader_top    = dumpM damagePodium_Lb
q_trial_running = dumpM ledgerWithBalance_Tb
q_trial_moving  = dumpM ledgerWithTrend_Tb
q_share_two     = dumpM bookWithShares_Rs
q_share_one     = dumpM bookWithRegionShare_Rs
q_ward_pipeline = dumpM rosterPipeline_Wr
q_branch_trend  = dumpM withTrend_Bd
q_media_top     = dumpM topChannels_Ms
q_claims_decile = dumpM severityDeciles_Ce
q_claims_fraud  = dumpM fraudRanks_Ce

-- Pivots: expected to PANIC when forced (Native.Record.scalaRecord#).
q_pivot_quarter = dumpL revenueByQuarter_Sl
q_pivot_line    = dumpL revenueByLine_Sl
q_pivot_survey  = dumpL meanWide_Sp
q_pivot_media   = dumpL spendByChannel_Ms
q_pivot_default = dumpL spendByChannelFilled_Ms
q_pivot_claims  = dumpL incurredByStatus_Ce

-- The suspected root cause, probed directly.
probeRecord      = record# { q = 1 }
probeScalaRecord = scalaRecord# (record# { q = 1 })
probeAll         = all_Pred { q = 1 }
