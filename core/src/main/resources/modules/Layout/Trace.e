module Layout.Trace where

-- The render trace as Ermine DATA (DB programme S2f; tracker/db/OBSERVABILITY.md
-- section "The trace as Ermine data").
--
-- Every `ermine/render` answer from a job that ran carries a `trace`
-- (lsp/TraceJson.scala; the schema is OBSERVABILITY.md section 4).  `Trace`
-- mirrors that JSON key for key, so json/Decode.scala reads a saved trace as
-- a report's PARAMETERS: `Ermine: Save Render Trace` writes the current
-- answer's trace to a params file, and a `Trace -> Node` report
-- (core/src/test/resources/modules/Doc/TraceReport.e) renders it through the
-- ordinary preview path.
--
-- The decoding rules that shape these types (json/Decode.scala's header):
--   * a record-style constructor is a CLOSED object keyed by its field
--     names, so every key the server emits is a field here, and a key this
--     declaration does not know is refused ("the key ... is not allowed
--     here") -- except inside the two `Spread Json` fields below;
--   * a field declared `Maybe a` is an OPTIONAL key (absent -> Nothing).
--     A `Nullable` field is not: it needs the key, holding null.  The server
--     leaves optional keys OUT (TraceJson: "never null"), so they are Maybe;
--   * `generation` is whatever the answer's generation was, so it is `Json`;
--   * `table` (a setup entry) and `database` (the connection) are Ermine
--     keywords and cannot be fields: each record that carries one has a
--     `Spread Json` that gathers it, and the helpers below read it back.
--
-- One module per nested record (Layout/Trace/*.e), because a selector is a
-- module-global name and `ms`, `rows`, `path`, `sql`, `kind`, `queries` ...
-- are keys of more than one of them.  The helpers here match positionally,
-- so a report needs only this module.
--
-- The relations are built with `relationWithHeader`, so a trace with no
-- queries or no phases still gives typed, EMPTY relations with their
-- columns (a plain `relation []` has none and the runner answers 500: the
-- Q21 lesson, tracker/JSON-WIDGET-PLAYGROUND.md WP-29).

import Bool
import Eq
import Function
import Json
import List using {map_List; length; foldl; zipIndex; filter; empty_Bracket; cons_Bracket}
import Maybe
import Native.Object using toString
import Num using toDouble
import Primitive
import Relation
import Relation.Row using {single_Brace; snoc_Brace}
import String using (++)
export Layout.Trace.Phase using type TracePhase; TracePhase
export Layout.Trace.Setup using type TraceSetup; TraceSetup
export Layout.Trace.Query using type TraceQuery; TraceQuery
export Layout.Trace.Totals using type TraceTotals; TraceTotals
export Layout.Trace.Connection using type TraceConnection; TraceConnection
export Layout.Trace.Running using type TraceRunning; TraceRunning
export Layout.Trace.Truncated using type TraceTruncated; TraceTruncated

-- The whole trace, the top-level keys in TraceJson's order.
data Trace = Trace { v          : Int
                   , generation : Json
                   , partial    : Bool
                   , wallMs     : Double
                   , phases     : List TracePhase
                   , queries    : List TraceQuery
                   , totals     : TraceTotals
                   , connection : TraceConnection
                   , running    : Maybe TraceRunning
                   , truncated  : Maybe TraceTruncated }

-- ------------------------------------------------------------------------
-- the columns of the relations below (prefixed: `path`, `ms` ... are the
-- selectors of the records above)

-- traceQueries: one row per relation, in execution order
field tqOrder    : Int      -- 1-based execution order
field tqPath     : String   -- the relation's $-path
field tqDelivery : String   -- fetched | inline | deferred, "(failed)" appended on error
field tqDialect  : String   -- "" when no SQL ran
field tqRowsRead : Int      -- rows the database returned
field tqRows     : Int      -- rows handed to the report
field tqDbMs     : Double   -- setup + execute + fetch
field tqMs       : Double   -- the relation's wall time
field tqShare    : Double   -- tqMs / the trace's wallMs, 0..1

-- traceSql: one row per relation that ran SQL
field tsOrder     : Int
field tsPath      : String
field tsSql       : String  -- capped at 16 KiB by the server, with its marker
field tsSqlBytes  : Int     -- the FULL length before any cap
field tsSetup     : String  -- "memo MemoHash_9f2c41 (reused), load t12" or ""

-- tracePhases: one row per phase, pipeline order
field tpOrder : Int
field tpPhase : String
field tpLabel : String      -- "01 session": a relation has no row order, so
                            -- the chart's ascending category axis needs the
                            -- pipeline position in the label
field tpMs    : Double
field tpShare : Double      -- of wallMs (phases are disjoint and sum to it)
field tpHow   : String      -- measured | attributed | cached

-- traceTimes / traceRowCounts: label/value pairs for a scorecard
field tkLabel : String
field tkValue : Double

-- ------------------------------------------------------------------------
-- the numbers

traceWallMs : Trace -> Double
traceWallMs (Trace _ _ _ w _ _ _ _ _ _) = w

traceTotals : Trace -> TraceTotals
traceTotals (Trace _ _ _ _ _ _ t _ _ _) = t

traceDbMs : Trace -> Double
traceDbMs t = case traceTotals t of TraceTotals d _ _ _ _ _ _ _ _ _ -> d

traceOtherMs : Trace -> Double
traceOtherMs t = case traceTotals t of TraceTotals _ o _ _ _ _ _ _ _ _ -> o

traceQueueMs : Trace -> Double
traceQueueMs t = case traceTotals t of TraceTotals _ _ _ q _ _ _ _ _ _ -> q

traceQueryCount : Trace -> Int
traceQueryCount t = case traceTotals t of TraceTotals _ _ _ _ _ q _ _ _ _ -> q

traceRelationCount : Trace -> Int
traceRelationCount t = case traceTotals t of TraceTotals _ _ _ _ r _ _ _ _ _ -> r

traceRowsRead : Trace -> Int
traceRowsRead t = case traceTotals t of TraceTotals _ _ _ _ _ _ r _ _ _ -> r

traceRowsUsed : Trace -> Int
traceRowsUsed t = case traceTotals t of TraceTotals _ _ _ _ _ _ _ r _ _ -> r

traceIsPartial : Trace -> Bool
traceIsPartial (Trace _ _ p _ _ _ _ _ _ _) = p

traceGeneration : Trace -> String
traceGeneration (Trace _ g _ _ _ _ _ _ _ _) = render g

-- the largest single relation's wall time (0 with none)
traceSlowestMs : Trace -> Double
traceSlowestMs (Trace _ _ _ _ _ qs _ _ _ _) =
  foldl (a q -> if (queryMs q > a) (queryMs q) a) 0.0 qs

-- ------------------------------------------------------------------------
-- the text

-- a string key of a Spread's object, or ""
spreadString : String -> Spread Json -> String
spreadString k (Spread (JObj kvs)) =
  foldl (acc kv -> case kv of
                     (k', JStr s) -> if (k' == k) s acc
                     _            -> acc) "" kvs
spreadString _ _ = ""

-- "sales-mssql (mssql) / ErmineSales" or "in-memory sqlite"
traceConnectionLine : Trace -> String
traceConnectionLine (Trace _ _ _ _ _ _ _ (TraceConnection k d p more) _ _) =
  let db = spreadString "database" more
      named = maybe (k ++ " " ++ d) (n -> n ++ " (" ++ d ++ ")") p
  in if (db == "") named (named ++ " / " ++ db)

-- what the trace does NOT cover, in words, or ""
traceCaveat : Trace -> String
traceCaveat (Trace _ _ partial _ _ _ _ _ running truncated) =
  let r = maybe "" (x -> case x of
                            TraceRunning p ph _ since ->
                              "partial: still running " ++ maybe (maybe "?" id ph) id p ++
                              " after " ++ toString since ++ " ms. ") running
      c = maybe "" (x -> case x of
                            TraceTruncated n short ->
                              toString n ++ " entries were dropped by the trace's caps" ++
                              (if short " and every SQL text was cut to 1 KiB" "") ++ ". ") truncated
  in (if (partial && r == "") "partial: the watchdog answered before the render finished. " "") ++ r ++ c

-- ------------------------------------------------------------------------
-- the relations

queryMs : TraceQuery -> Double
queryMs (TraceQuery _ _ _ _ _ _ _ _ _ _ _ m _ _ _ _ _ _ _ _ _) = m

shareOf : Double -> Double -> Double
shareOf wall x = if (wall > 0.0) (x / wall) 0.0

-- One row per relation, in execution order.
traceQueries : Trace -> [tqOrder, tqPath, tqDelivery, tqDialect, tqRowsRead, tqRows, tqDbMs, tqMs, tqShare]
traceQueries (Trace _ _ _ wall _ qs _ _ _ _) =
  relationWithHeader {tqOrder, tqPath, tqDelivery, tqDialect, tqRowsRead, tqRows, tqDbMs, tqMs, tqShare}
    (map_List (iq -> case iq of
       (i, TraceQuery p del d _ _ _ _ _ _ _ db m rr r _ _ _ _ _ err _) ->
         { tqOrder = i + 1, tqPath = p
         , tqDelivery = if (maybe False id err) (del ++ " (failed)") del
         , tqDialect = maybe "" id d, tqRowsRead = rr, tqRows = r
         , tqDbMs = db, tqMs = m, tqShare = shareOf wall m }) (zipIndex qs))

setupLine : TraceSetup -> String
setupLine (TraceSetup k c _ e more) =
  let t = spreadString "table" more
  in k ++ (if (t == "") "" (" " ++ t)) ++
     maybe "" (b -> if b " (created)" " (reused)") c ++
     (if (maybe False id e) " (failed)" "")

joinWith : String -> List String -> String
joinWith _ [] = ""
joinWith s (x :: xs) = foldl (a y -> a ++ s ++ y) x xs

-- One row per relation that ran SQL (a deferred relation ran none).
traceSql : Trace -> [tsOrder, tsPath, tsSql, tsSqlBytes, tsSetup]
traceSql (Trace _ _ _ _ _ qs _ _ _ _) =
  relationWithHeader {tsOrder, tsPath, tsSql, tsSqlBytes, tsSetup}
    (map_List (iq -> case iq of
       (i, TraceQuery p _ _ s b _ su _ _ _ _ _ _ _ _ _ _ _ _ _ _) ->
         { tsOrder = i + 1, tsPath = p, tsSql = maybe "" id s, tsSqlBytes = maybe 0 id b
         , tsSetup = joinWith ", " (map_List setupLine (maybe [] id su)) })
       (filter (iq -> case iq of (_, TraceQuery _ _ _ s _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _) -> maybe False (_ -> True) s)
               (zipIndex qs)))

-- 7 -> "07"
padded : Int -> String
padded n = if (n < 10) ("0" ++ toString n) (toString n)

-- One row per phase, in pipeline order.
tracePhases : Trace -> [tpOrder, tpPhase, tpLabel, tpMs, tpShare, tpHow]
tracePhases (Trace _ _ _ wall ps _ _ _ _ _) =
  relationWithHeader {tpOrder, tpPhase, tpLabel, tpMs, tpShare, tpHow}
    (map_List (ip -> case ip of
       (i, TracePhase n m a c) ->
         { tpOrder = i + 1, tpPhase = n, tpLabel = padded (i + 1) ++ " " ++ n, tpMs = m, tpShare = shareOf wall m
         , tpHow = if (maybe False id c) "cached" (if (maybe False id a) "attributed" "measured") }) (zipIndex ps))

-- wall / db / other / queue, in ms.  A relation has no row order and the
-- rows come back sorted, so each label carries its position ("1 wall").
traceTimes : Trace -> [tkLabel, tkValue]
traceTimes t =
  relationWithHeader {tkLabel, tkValue}
    [ { tkLabel = "1 wall",  tkValue = traceWallMs t }
    , { tkLabel = "2 db",    tkValue = traceDbMs t }
    , { tkLabel = "3 other", tkValue = traceOtherMs t }
    , { tkLabel = "4 queue", tkValue = traceQueueMs t } ]

-- rows the database returned vs rows the report used
traceRowCounts : Trace -> [tkLabel, tkValue]
traceRowCounts t =
  relationWithHeader {tkLabel, tkValue}
    [ { tkLabel = "1 rows read", tkValue = toDouble (traceRowsRead t) }
    , { tkLabel = "2 rows used", tkValue = toDouble (traceRowsUsed t) }
    , { tkLabel = "3 queries",   tkValue = toDouble (traceQueryCount t) } ]
