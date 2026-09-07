module Time.Helpers where

{- ROW-POLYMORPHIC HELPERS FOR DATE-KEYED REPORTING: the "as of" family, calendar
   bucketing, fill-forward, period-over-period change, moving statistics, money
   conversion and nullable arithmetic.

   Every report in `core/examples/Time` is built out of these. Each helper names
   only the columns it touches and carries the rest of the row through as a row
   variable; the partition constraints in the signatures are what says so. Read
   `r <- (h, t)` as "the row r is exactly the disjoint union of h and t", so a
   caller may pass any relation carrying the named columns plus anything else.

   ---------------------------------------------------------------------------
   WHY THIS FILE EXISTS AT ALL

   `Relation.e` ships EIGHT date-keyed combinators -- `lookupLatest`,
   `lookupLatest1`, `lookupLatestWithin`, `lookupLatestWithin1`, `lookupLatest'`,
   `nearestDate`, `nearestDateWithin` and `lookbackJoin` -- and before this
   directory only ONE of them had a use anywhere in `core/examples`:
   `nearestDateWithin`, in `incomplete/RunCalibration.e` and
   `incomplete/Signatures.e`, where it is the subject of a study of the SOLVER
   rather than a report a user learns from (`lookbackJoin` is discussed there but
   not called). `Wide/BranchDeposits.e`, written concurrently with this
   directory, calls `lookupLatest`. Every one of the eight has a call site here.
   They are the backbone of every dated report ever written ("the FX rate as of
   the invoice date", "the last reading before the review date", "the headcount on
   the first of the month") and a reader of `core/examples` would not have known
   they existed.

   Three of them have a defect a user hits immediately, recorded here because
   the fix is a helper rather than a patch:

     `lookupLatest` and friends group by the DATE ALONE (`groupBy {ffine}` inside
     `nearestDate`). For a one-series history that is right. For a history keyed
     by station / sensor / employee -- which is every real history -- it takes the
     GLOBALLY latest date and returns whatever rows happen to sit on it, so a
     series that stopped reporting last week silently disappears instead of
     carrying its last value forward. `nearestBy` below is the per-key version:
     the same body with the key row appended to the grouping row.

   ---------------------------------------------------------------------------
   THE RULE THIS FILE OBEYS, inherited from `core/examples/Ai/Common.e`

   A row-polymorphic helper is only useful if its CALL SITES check. `Ai/Common.e`
   found that bundling `if`'s four-constraint `RUnion3` into a helper's signature
   on top of `combine`'s `RUnion2` hangs the compiler, and concluded: keep the
   conditional at the call site, let the helper take a ready-made `Op`.

   MEASURED AGAIN HERE, at the row-solver defaults adopted at fe024a7
   (`-Dermine.rowSound` ON, `dequeuePolicy=smallcanon`, `solveBudget=20000`):
   THE CLIFF IS GONE. The bundled form -- conditional AND `combine` in one
   relation-returning helper, the row `Ai/Common.e` records as never finishing --
   checks in about a fifth of a second, and so do the other three forms; all four
   are now within noise of each other (`tracker/loopmodel/E3-EXAMPLES.md` §5).

   Nor does `if` leave an `RUnion3` behind in what a helper PUBLISHES. `safeDiv`
   and `band3`/`band4` below are `if`-based, and their SHIPPED signatures carry
   one row constraint and none at all respectively; the `RUnion3` lattice appears
   only in the type the compiler INFERS, and even there it grinds down to five
   constraints for `safeDiv` and to the single tautology `v <- (v)` for `band3`
   and `band4` (`Time/Signatures.e` carries all of them verbatim).
   SINCE STAGE S3 (2026-09-07) it grinds down further still, because the
   simplifier now deletes the tautology and permuted duplicate partitions from a
   published residual: `safeDiv`'s five are THREE (its two permuted pairs were
   one constraint each), and `band3`/`band4` infer NO row constraint at all. So
   the measurement this paragraph reports is now stronger than it was: an
   `Op`-returning conditional over one column costs three constraints for a
   guarded division and NOTHING for a band, however deeply nested.

   The conditionals here still return `Op`s and let the caller feed them to
   `combine`, but the reason is now composability, not the solver: `band3` is
   called on four different value types in four different reports, which a
   relation-returning form could not be.
   ---------------------------------------------------------------------------
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Op.Type using type Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Relation.Aggregate.Type using type Aggregate
import Relation.Row as Rw
import Relation.Sort as Sort
import Relation.Windowed as W
import Syntax.Relation
import Date

-- ===================================================================== as of

-- | The rows of a history relation current AS OF one date: the rows carrying
-- the latest value of the date column that is not after `d`, looking back
-- arbitrarily far. This is the "reading as of", "rate as of", "status as of"
-- query, and it is `Relation.lookupLatest1` under a signature that says what it
-- does. The constraint `r <- (t, h)` names the date column `h` and carries
-- everything else through as `t`, so a 30-column fact table passes unchanged.
--
-- CAUTION -- the lookback is over the WHOLE relation, not per key; see
-- `nearestBy` for the per-key form.
asOf : forall h t r. r <- (t, h) => Field h Date -> Date -> Relation r -> Relation r
asOf = lookupLatest1

-- | `asOf` against a whole relation of as-of dates rather than one: for each
-- date in `ds`, the rows current on it. `Relation.lookupLatest`.
asOfEach : forall h t r. r <- (t, h)
        => Field h Date -> Relation h -> Relation r -> Relation r
asOfEach = lookupLatest

-- | `asOf` with a STALENESS WINDOW: a row is only accepted if its date is
-- within `n` days of the as-of date. A rate that has not been published for a
-- fortnight is not a rate, it is a stale quote, and this is how a report says
-- so -- the rows simply do not come back and the outer join shows a gap.
--
-- The window is expressed as an upper bound function on the history date, which
-- is `Relation.lookupLatestWithin1`'s calling convention.
--
-- READ THE SEMANTICS BEFORE USING IT. `nearestDateWithin` filters to
-- `histDate <= asOfDate <= histDate + n days` and then takes
-- `groupBy {asOfDate} (maxRowBy histDate)` -- ONE group, because there is one
-- as-of date -- so the answer is the rows on the single latest history date
-- inside the window, or nothing. It is therefore a BINARY GATE on `asOf`'s
-- answer, not a per-row staleness filter: whenever the globally latest date at
-- or before `d` falls inside the window the result is exactly `asOf`'s, and
-- whenever it does not the result is EMPTY. It cannot return a series' own older
-- row in place of a fresher one from another series -- that is finding (1) about
-- date-alone grouping again, and `nearestBy` is the answer to it.
-- `Time.ReadingHistory` shows all three answers side by side.
asOfWithin : forall h t r. r <- (h, t)
          => Int -> Field h Date -> Date -> Relation r -> Relation r
asOfWithin n f d r = lookupLatestWithin1 (g -> dateAdd_Op n days (col_Op g)) f d r

-- | PER-KEY as-of, one date at a time, by recursive lookback: for every row of
-- `keys` take the history row on the latest date at or before `d`, walking back
-- a day at a time and stopping at `oldest`. This is `Relation.lookupLatest'`,
-- whose recursion is the only place in the stdlib where a date lookup is
-- guaranteed to return a row PER KEY.
--
-- It is quadratic in the lookback length -- one union per day -- so keep
-- `oldest` close. `nearestBy` does the same job set-at-a-time.
latestPerKey : forall dr hist keys out.
               (exists kc kt ho hd. keys <- (kc, kt), hist <- (ho, kc)
               , hist <- (dr, hd), out <- (ho, keys), out <- (ho, kc, kt))
            => Field dr Date -> Relation hist -> Date -> Date
            -> Relation keys -> Relation out
latestPerKey dateF hist oldest d keys =
  lookupLatest' (dd ks -> join ks (filterEq dateF dd hist)) oldest d keys

-- | The stdlib's `nearestDate`, named: map each SPARSE date to the nearest FINE
-- date at or after it. Grouping is by the fine date alone.
--
-- WATCH THE ARITY. `Field rsparse Date` and `Relation rsparse` share a row
-- variable, and a `Field`'s row is the SINGLETON row of that one column -- so
-- the sparse relation must be the projected date column and nothing else. This
-- combinator maps dates to dates; joining the result back onto the facts is the
-- caller's job (`Relation.lookupLatest` does exactly that, with `r # {f}`).
-- Passing a wide relation instead gives
--     failed to unify type (|readDate|) with type (|... every column ...|)
-- `nearestBy` below takes the whole relation and is the form a report wants.
nearest : forall rsparse rfine r.
          r <- (rsparse, rfine)
       => Field rsparse Date -> Relation rsparse
       -> Field rfine Date -> Relation rfine -> Relation r
nearest = nearestDate

-- | `nearestDate` with a WINDOW: `Relation.nearestDateWithin`, with the upper
-- bound fixed to `n` days after the sparse date. Same single-column arity trap
-- as `nearest`, and the same one-group collapse described under `asOfWithin`.
nearestWithin : forall rsparse rfine r.
                r <- (rsparse, rfine)
             => Int -> Field rsparse Date -> Relation rsparse
             -> Field rfine Date -> Relation rfine -> Relation r
nearestWithin n fs rs ff rf =
  nearestDateWithin (g -> dateAdd_Op n days (col_Op g)) fs rs ff rf

-- | `asOfEach` with a window: `Relation.lookupLatestWithin`, the form that takes
-- a whole RELATION of as-of dates rather than one. The group is then per as-of
-- date, so unlike `asOfWithin` this one really does return several rows -- one
-- date's worth per requested date.
asOfEachWithin : forall h out. Has out h
              => Int -> Field h Date -> Relation h -> Relation out -> Relation out
asOfEachWithin n f ds r =
  lookupLatestWithin (g -> dateAdd_Op n days (col_Op g)) f ds r

-- | `Relation.lookbackJoin`, the eighth date-keyed combinator: join two
-- relations on their common columns, substituting for each left row the nearest
-- RIGHT date at or before its own, within `n` days. Unlike the `lookupLatest`
-- family this one is a JOIN -- it keeps both sides' columns and the date column
-- in the result is the RIGHT one, which is what a rescaling run wants ("read
-- against the reference in force on that day").
--
-- `lookbackJoin` has no signature in the stdlib and its inferred residual is the
-- fifteen-constraint, run-to-run-unstable one that
-- `core/examples/incomplete/RunCalibration.e` is an entire module about. The
-- signature below is the specialisation `incomplete/Signatures.valueAsOfSimple`
-- proves that body has -- one constraint per join leg, which is what a person
-- writes.
lookback : forall k s t r1 r2 r3.
           (r1 <- (k, s), r2 <- (k, t), r3 <- (k, s, t))
        => Int -> Field k Date -> Relation r1 -> Relation r2 -> Relation r3
lookback n f r1 r2 = lookbackJoin (g -> dateAdd_Op n days (col_Op g)) f r1 r2

-- | PER-KEY nearest date -- the combinator `Relation.e` is missing.
--
-- `nearestDate` is `groupBy {ffine} (maxRowBy fsparse)` over the join filtered
-- to `fsparse <= ffine`. That grouping row is the fine date ALONE, so with a
-- multi-series history the maximum is taken across series and a series whose
-- last observation is older than another's drops out entirely. `nearestBy` is
-- the identical body with the caller's key row appended to the grouping row, so
-- the maximum is taken WITHIN each key.
--
-- `keyRow` must be common to both relations (it is what the join lines up on).
--
-- Its inferred residual carries a tautology and a permuted duplicate; see
-- `Time.Signatures.nearestByFull` / `nearestByDeduped` for the pair and the
-- proof that the shorter set says the same thing.
nearestBy : forall k sd fd sparse fine out a.
            (exists sv fv. sparse <- (k, sd, sv), fine <- (k, fd, fv)
            , out <- (k, sd, sv, fd, fv), Primitive a)
         => Row k -> Field sd a -> Relation sparse
         -> Field fd a -> Relation fine -> Relation out
nearestBy keyRow fsparse rsparse ffine rfine =
  materialize ' groupBy (snoc_Rw keyRow ffine) (maxRowBy fsparse)
                        ([| fsparse <= ffine |] (join rsparse rfine))

-- | CARRY THE LAST KNOWN VALUE FORWARD across a calendar.
--
-- `fillForward keyRow obsDate observations calDate calendar` crosses the
-- calendar with the distinct keys that appear in `observations` -- that cross
-- product is the SPINE, the (key, day) grid the report wants a value on -- and
-- then takes each key's latest observation at or before each day. Days before a
-- key's first observation get no row; days after its last one repeat it, which
-- is exactly what "last known" means.
--
-- This is the one helper here that is not in the stdlib in any form, and it is
-- the query a sensor / inventory / meter report cannot do without.
-- The key row may OVERLAP the calendar: `ck` below is the shared part (a
-- session calendar keyed by `network`, joined to a key of
-- `{station, network}`), and `ko` the rest of the key. When they are disjoint
-- -- the usual case, a plain day calendar -- `ck` is empty and the signature
-- reads as `out <- (k, od, ov, cd, cv)`.
fillForward : forall k ko ck od cd obs cal out a.
              (exists ov cv. k <- (ko, ck), cal <- (cd, ck, cv)
              , obs <- (ko, ck, od, ov)
              , out <- (ko, ck, od, ov, cd, cv), Primitive a)
           => Row k -> Field od a -> Relation obs
           -> Field cd a -> Relation cal -> Relation out
fillForward keyRow obsF obs calF cal =
  nearestBy keyRow obsF obs calF (join cal (obs # keyRow))

-- ================================================================= calendars

-- | ASSIGN EACH FACT TO THE CALENDAR BUCKET CONTAINING ITS DATE.
--
-- A calendar here is any relation of half-open-in-spirit ranges -- a fiscal
-- month table, a 4-4-5 period table, a set of billing periods, an employment
-- spell -- carrying a start column and an end column plus whatever labels the
-- report wants (`periodName`, `fiscalYear`, `quarter`). Facts carry a date.
-- The result is the cross product filtered to the rows whose date falls in the
-- range, so every fact gains its bucket's labels and a fact outside every
-- bucket drops out.
--
-- The bounds are INCLUSIVE at both ends; a calendar whose ranges touch will
-- duplicate facts on the boundary day. That is the caller's business and the
-- reason the helper does not close the interval for you.
bucketBy : forall s e d cal facts out rel.
           (exists cv fv. cal <- (s, e, cv), facts <- (d, fv)
           , out <- (s, e, cv, d, fv), RelationalComb rel)
        => Field s Date -> Field e Date -> Field d Date
        -> rel cal -> rel facts -> rel out
bucketBy startF endF dateF cal facts =
  [| startF <= dateF, dateF <= endF |] (join facts cal)

-- | The number of whole days from `s` to `e`, as an `Op` usable in `combine`.
--
-- FINDING, recorded in the report: `Relation.Op.dateDiff` is declared
--     dateDiff# : PrimitiveTemporal d => TimeUnit -> Op r d -> Op r1 d -> Op r2 Int
-- with the RESULT row `r2` unconstrained by either argument's row, and its
-- wrapper `dateDiff` (Relation/Op.e:151) has NO SIGNATURE AT ALL -- the line
-- that would have given it one is commented out immediately above. So a
-- `combine` of `dayCount` type-checks even when neither date column is in the
-- relation being combined: the header computation then fails at run time with
-- `Operation refers to nonexistent column`. A static guarantee every other `Op`
-- combinator enforces is, for date differences alone, deferred to run time.
-- `dateAdd` does NOT have the hole -- its wrapper ties the rows -- so the fix is
-- one signature. The signature below repeats the hole rather than hiding it,
-- because tightening it would be a stdlib change and this directory is examples.
dayCount : forall r r1 out. Field r Date -> Field r1 Date -> Op out Int
dayCount s e = dateDiff_Op days (col_Op s) (col_Op e)

-- | Year fraction on the ACT/365 FIXED day-count convention: whole days divided
-- by 365. What a sterling accrual uses.
yearFrac365 : forall r r1 out. Field r Date -> Field r1 Date -> Op out Double
yearFrac365 s e = fromNumericOp_Op (dayCount s e) /_Op prim_Op 365.0

-- | Whole MONTHS between two date columns -- the period index a cohort report
-- and a period-over-period report both need, derived rather than carried.
--
-- `Relation.Op` exposes exactly one date-arithmetic primitive pair, `dateAdd`
-- and `dateDiff`; there is no `year`/`month`/`quarter` op, so a period label has
-- to come from a calendar table (see `bucketBy`) and a period INDEX has to come
-- from a difference like this one.
monthsBetween : forall r r1 out. Field r Date -> Field r1 Date -> Op out Int
monthsBetween s e = dateDiff_Op months (col_Op s) (col_Op e)

-- | Whole months from a FIXED epoch to a date column: a dense integer month
-- index over the whole table, which is what makes `shiftBy` (below) able to
-- express "the same month last year" as arithmetic.
monthsSince : forall r out. Date -> Field r Date -> Op out Int
monthsSince d f = dateDiff_Op months (prim_Op d) (col_Op f)

-- | Whole days from a fixed epoch to a date column.
daysSince : forall r out. Date -> Field r Date -> Op out Int
daysSince d f = dateDiff_Op days (prim_Op d) (col_Op f)

-- | Whole days from a date COLUMN up to a fixed date -- the mirror of
-- `daysSince`, and the one a TENURE or AGE column needs ("how long ago was this
-- person hired, as of the reporting date").
daysUntil : forall r out. Field r Date -> Date -> Op out Int
daysUntil f d = dateDiff_Op days (col_Op f) (prim_Op d)

-- | Age or tenure in YEARS on a given date: days over 365.25, which is the
-- convention an HR report uses and is not any of the accrual ones.
yearsOn : forall r out. Date -> Field r Date -> Op out Double
yearsOn d f = fromNumericOp_Op (daysUntil f d) /_Op prim_Op 365.25

-- | Year fraction on ACT/360, the convention for USD and EUR deposits. The
-- same numerator over a 360-day year, which is why an ACT/360
-- deposit pays about 1.4% more interest than the same rate on ACT/365.
yearFrac360 : forall r r1 out. Field r Date -> Field r1 Date -> Op out Double
yearFrac360 s e = fromNumericOp_Op (dayCount s e) /_Op prim_Op 360.0

-- =============================================================== money, rates

-- | MULTIPLY A MONEY COLUMN BY A RATE COLUMN into a new column: the FX
-- conversion, once the rate has been joined on (by `asOf`, usually).
--
-- Both columns must already be in the row. Keeping the join OUT of this helper
-- is deliberate -- the rate lookup is `asOf`'s job, and a helper that did both
-- would carry the lookback's residual and this one's at every call site.
fxConvert : forall amt rate out r t rel n.
            (exists o. r <- (amt, rate, o), t <- (r, out)
            , PrimitiveNum n, RelationalComb rel)
         => Field amt n -> Field rate n -> Field out n -> rel r -> rel t
fxConvert amtF rateF outF = combine_Op (col_Op amtF *_Op col_Op rateF) outF

-- | Simple interest for one accrual period: principal * rate * yearFraction,
-- with the year fraction supplied by the caller as an `Op` so the day-count
-- convention stays visible at the call site instead of being buried here.
accrual : forall p rt yr out opr n.
          (out <- (p, rt, yr), PrimitiveNum n, AsOp opr)
       => Field p n -> Field rt n -> opr yr n -> Op out n
accrual prinF rateF yf = col_Op prinF *_Op col_Op rateF *_Op yf

-- ============================================== period-over-period arithmetic

-- | Fractional change from `prior` to `cur`: `(cur - prior) / prior`. The
-- month-over-month and year-over-year growth every revenue report prints,
-- expressed once.
--
-- Both columns must be on the row -- put the prior period's value there with a
-- shifted self-join first (`Time.SubscriptionWaterfall` shows the join).
--
-- Its residual carried `r1 <- (r1)`, the tautology, until stage S3 (2026-09-07)
-- taught the simplifier to delete it; five inferred constraints became four.
-- See `Time.Signatures.pctChangeFull` / `pctChangeDeduped`.
pctChange : forall cur prior out n.
            (out <- (cur, prior), PrimitiveNum n)
         => Field cur n -> Field prior n -> Op out n
pctChange curF priorF = (col_Op curF -_Op col_Op priorF) /_Op col_Op priorF

-- | The same difference as a RATIO rather than a change: `cur / prior`. A
-- retention or index report wants 1.05, not 0.05.
indexOf : forall cur prior out n.
          (out <- (cur, prior), PrimitiveNum n)
       => Field cur n -> Field prior n -> Op out n
indexOf curF priorF = col_Op curF /_Op col_Op priorF

-- | SHIFT A PERIOD-INDEXED RELATION FORWARD by `n` periods, renaming its
-- measure on the way, so that joining the result back to the original puts
-- period t-n's value beside period t's.
--
--     lastMonth = shiftBy monthIx mrr priorMrr 1 monthly
--     mom       = combine_Op (pctChange mrr priorMrr) momPct (join monthly lastMonth)
--
-- The fresh column the shift needs is minted by `Field.withFieldCopy`, the same
-- trick `Relation.lookbackJoin` uses, so no name is burned in the caller's
-- namespace. `rename'` (remove the target, then rename onto it) is what makes
-- the shifted index land back on the original column name.
shiftBy : forall p v pv r out n a rel.
          (exists o. r <- (p, v, o), out <- (p, pv, o)
          , PrimitiveNum n, RelationalComb rel)
       => Field p n -> Field v a -> Field pv a -> n -> rel r -> rel out
shiftBy pF vF pvF n r =
  withFieldCopy pF (p' ->
    r |> combine_Op (col_Op pF +_Op prim_Op n) p'
      |> rename' p' pF
      |> rename vF pvF)

-- ====================================================== nullable arithmetic

-- | A nullable `Op` made total by substituting zero for null: `coalesce`.
--
-- Its inferred residual WAS `v <- (v)` -- the TAUTOLOGY, a row is the disjoint
-- union of itself -- which every row satisfies and which therefore says
-- nothing. `Time.Signatures.orZeroFull` carries it verbatim and
-- `orZeroSimple` discharges it with nothing in scope, which is the proof that
-- the constraint is noise. Stage S3 (2026-09-07) acted on that proof: the
-- simplifier deletes `a <- (a)` now, so this body infers NO row constraint at
-- all. This is the same phenomenon
-- `core/examples/incomplete/Signatures.e` documents for `lookbackJoin`, reached
-- here from four characters of ordinary library code.
orZero : forall opc v. AsOp opc => opc v (Nullable Double) -> Op v Double
orZero x = coalesce_Op x (prim_Op 0.0)

-- | The same with a caller-chosen default, for the cases where zero is a lie
-- (a missing FX rate is not a rate of zero).
orElseNum : forall opc opa s t v a. (RUnion2 v s t, AsOp opc, AsOp opa)
         => opc s (Nullable a) -> opa t a -> Op v a
orElseNum = coalesce_Op

-- | ZERO-SAFE DIVISION as an `Op`: `n / d` where `d` is non-zero, else zero.
--
-- This is the `if`-in-a-helper shape `Ai/Common.e` warns about: `if` alone
-- contributes `RUnion3`, a four-constraint inclusion-exclusion lattice over
-- three row variables. At the adopted defaults it grinds down to FIVE inferred
-- constraints, of which two are permuted copies, so the shipped signature below
-- is ONE (`Time.Signatures.safeDivFull` / `safeDivDeduped` / `safeDivSimple`
-- carry the chain and prove the equivalences). It checks in well under a second,
-- and so does the bundled relation-returning form -- see the header of this
-- file.
safeDiv : forall num den out.
          out <- (num, den)
       => Field num Double -> Field den Double -> Op out Double
safeDiv n d = if_Op (col_Op d !=_Pred prim_Op 0.0)
                    (col_Op n /_Op col_Op d)
                    (prim_Op 0.0)

-- | Sum a column that may be null. `Relation.Aggregate.sum` is already
-- polymorphic in `PrimitiveNum`, and `Nullable Double` is a `PrimitiveNum`, so
-- this needs no special aggregate -- the point of the helper is to SAY that,
-- because a reader who has met SQL expects to have to write `sum(coalesce(x,0))`
-- and here the nulls are skipped for free.
nullSum : forall h b rel n. (Has b h, PrimitiveNum n, RelationalComb rel)
       => Field h n -> rel b -> rel h
nullSum f r = aggregate_Agg (sum_Agg (col_Op f)) f r

-- | Rows where the column IS null, and rows where it is not: the two halves a
-- data-quality panel prints side by side.
missing : forall h r rel a. (Has r h, Relational rel) => Field h a -> rel r -> rel r
missing f = selectNulls_Pred (col_Op f)

present : forall h r rel a. (Has r h, Relational rel) => Field h a -> rel r -> rel r
present f = selectNotNulls_Pred (col_Op f)

-- ======================================================= moving statistics

-- | A MOVING AGGREGATE over a date-ordered frame: `movingAgg agg part dateF n`
-- is `agg` applied to the `n` rows preceding each row plus the row itself,
-- within each partition of `part`, ordered by `dateF`.
--
-- `Relation.Windowed` is a whole stdlib module with no example at all. This is
-- the framed half of it (`core/examples/Wide` owns rank / ntile / pivot).
-- `Bounded n` / `Bounded 0` is "n back, none forward" -- a TRAILING window, the
-- only one a report may use without reading the future.
movingAgg : forall part dateR valR t n a.
            t <- (dateR, part, valR)
         => Aggregate valR n -> Row part -> Field dateR a -> Int -> Op t n
movingAgg agg partRow dateF n =
  windowed_W (windowedAggregate_W agg)
             (window_W partRow (single_Sort (dateF, Ascending_Sort))
                       (F_W (Bounded_W n) (Bounded_W 0)))

-- | Trailing mean of `valF` over `n + 1` rows -- the moving average a chart
-- draws over a noisy series. Its residual is `movingAgg`'s, one of whose three
-- constraints is redundant; see `Time.Signatures.movingMeanFull` /
-- `movingMeanDeduped`.
movingMean : forall part dateR valR t n a.
             (t <- (dateR, part, valR), PrimitiveNum n)
          => Row part -> Field dateR a -> Field valR n -> Int -> Op t n
movingMean partRow dateF valF n = movingAgg (mean_Agg (col_Op valF)) partRow dateF n

-- | Trailing sum: month-to-date, quarter-to-date, trailing-twelve-months.
movingSum : forall part dateR valR t n a.
            (t <- (dateR, part, valR), PrimitiveNum n)
         => Row part -> Field dateR a -> Field valR n -> Int -> Op t n
movingSum partRow dateF valF n = movingAgg (sum_Agg (col_Op valF)) partRow dateF n

-- | Trailing standard deviation -- the denominator of a z-score, and therefore
-- the outlier test a sensor report needs.
movingStdDev : forall part dateR valR t n a.
               (t <- (dateR, part, valR), PrimitiveNum n)
            => Row part -> Field dateR a -> Field valR n -> Int -> Op t n
movingStdDev partRow dateF valF n = movingAgg (stddev_Agg (col_Op valF)) partRow dateF n

-- | RUNNING total from the first row of the partition to the current one: the
-- cumulative line every waterfall draws. `Unbounded` back, none forward.
runningSum : forall part dateR valR t n a.
             (t <- (dateR, part, valR), PrimitiveNum n)
          => Row part -> Field dateR a -> Field valR n -> Op t n
runningSum partRow dateF valF =
  windowed_W (windowedAggregate_W (sum_Agg (col_Op valF)))
             (window_W partRow (single_Sort (dateF, Ascending_Sort))
                       (F_W Unbounded_W (Bounded_W 0)))

-- ======================================================== banding / buckets

-- | A THREE-WAY BAND on a numeric column: the label for "below `lo`", for
-- "below `hi`", and the label for everything else. Tenure bands, age bands,
-- ageing buckets on a receivables report, latency buckets -- all the same shape.
--
-- This is a NESTED conditional, so it carries `RUnion3` twice over. It checks,
-- and its call sites check, which is the measurement `Ai/Common.e` asked for at
-- the new defaults; the numbers are in `tracker/loopmodel/E3-EXAMPLES.md`.
band3 : forall v a b. (Primitive a, Primitive b)
     => Field v a -> a -> b -> a -> b -> b -> Op v b
band3 f lo loLbl hi hiLbl rest =
  if_Op (col_Op f <_Pred prim_Op lo)
        (prim_Op loLbl)
        (if_Op (col_Op f <_Pred prim_Op hi) (prim_Op hiLbl) (prim_Op rest))

-- | A FOUR-WAY band: three thresholds and a fallthrough. Three levels of nested
-- `if`, so three nested `RUnion3`s -- and its residual was the single tautology
-- `v <- (v)` and is now EMPTY (stage S3 deletes `a <- (a)`), which is the
-- measurement that says the conditional lattice collapses when every branch
-- reads one column. Age bands, ageing buckets, SLA buckets.
band4 : forall v a b. (Primitive a, Primitive b)
     => Field v a -> a -> b -> a -> b -> a -> b -> b -> Op v b
band4 f b1 l1 b2 l2 b3 l3 rest =
  if_Op (col_Op f <_Pred prim_Op b1) (prim_Op l1)
    (if_Op (col_Op f <_Pred prim_Op b2) (prim_Op l2)
      (if_Op (col_Op f <_Pred prim_Op b3) (prim_Op l3) (prim_Op rest)))
