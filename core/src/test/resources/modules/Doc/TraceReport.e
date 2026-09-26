module Doc.TraceReport where

-- The render trace, rendered BY ERMINE (DB programme S2f; tracker/db/
-- OBSERVABILITY.md section "The trace as Ermine data").
--
-- `report`'s PARAMETERS are a trace: the `trace` key of an `ermine/render`
-- answer, exactly as lsp/TraceJson.scala emits it, decoded into
-- Layout.Trace's `Trace`.  In the editor, `Ermine: Save Render Trace` writes
-- the current answer's trace to this report's params file
-- (.ermine/preview/Doc.TraceReport/report.params.json) and `Ermine: Preview
-- Render Trace` saves and then picks this report, so the preview panel draws
-- the trace of a render with the same typed widgets any report uses.
--
-- THE RECURSION RULE: this report's own render is traced like any other (its
-- answer carries a trace of the VALUES scans its tables cost), and saving
-- THAT trace over this params file replaces the trace it is showing -- which
-- is why the save asks before it replaces anything.
--
-- It needs no database: every relation is built from the trace's lists
-- (Layout.Trace, `relationWithHeader`), so it renders on the in-memory
-- SQLite connection and with an empty trace (no queries, no phases).  On a
-- held profile connection those relations are VALUES scans on the user's
-- database, one per widget, as for any literal relation.
--
--   sbt 'core/testOnly com.clarifi.reporting.TestRunner -- -f trace'
--
-- renders it over core/src/test/resources/doc/trace-sample.json.
-- (The sample predates F-1: its $.fetch[1] is the old in-memory `groupBy`, 388 rows read for 8; kept as is.)

import Json using type Inline; Inline
import Layout.Doc using {vflow; hflow; type Node}
import Layout.Trace
import Layout.Widgets.Format using {type CellFormat; Default; Round; Percentage; IntegralRound; Constant}
import Layout.Widgets.Headline using {headline; HeadlineProps}
import Layout.Widgets.Text using {plainText; TextProps}
import Layout.Widgets.Scorecard using {scorecard; scorecardOf; ScorecardSource}
import Layout.Widgets.Table using {tabular; simpleTable; col; numCol; withHeader; sortAsc; sortDesc}
import Layout.Widgets.Chart
import Layout.Widgets.AxisChart
import Layout.Widgets.PieChart
import List using {empty_Bracket; cons_Bracket}
import Maybe
import Native.Object using toString
import String using (++)

millis : CellFormat
millis = Round False False 1

share : CellFormat
share = Percentage False False 1 False

count : CellFormat
count = IntegralRound False False 0

-- "db 11.0 ms of 51.0 ms, 3 queries." (the connection is the headline's scope)
caption : Trace -> String
caption t =
  "db " ++ toString (traceDbMs t) ++ " ms of " ++
  toString (traceWallMs t) ++ " ms, " ++ toString (traceQueryCount t) ++ " queries. " ++
  traceCaveat t

report : Trace -> Node
report t =
  vflow
    -- the headline widget labels its three figures Rows / Total / Largest,
    -- so the scope says what they are here: relations, the render's wall ms
    -- (it includes work outside every relation, so it is more than their
    -- sum) and the slowest relation's ms
    [ headline (HeadlineProps ("Render trace, generation " ++ traceGeneration t)
                              (traceConnectionLine t ++
                               " · Rows = relations, Total = render wall ms, Largest = slowest relation ms")
                              (traceRelationCount t) (traceWallMs t) (traceSlowestMs t) millis)
    , plainText (TextProps (caption t))
    , hflow
        [ scorecard (scorecardOf (ScorecardSource "Time (ms)" tkLabel tkValue Nothing millis (Inline (traceTimes t))))
        , scorecard (scorecardOf (ScorecardSource "Rows" tkLabel tkValue Nothing count (Inline (traceRowCounts t)))) ]
    , axisChart (axisChartOf
        (ChartMeta "Time by phase (ms)"
          (ChartAxis "Phase" "Phase" Default (Scalar "String" False) True (Unscaled [Asc] []))
          (ChartAxis "ms" "ms" millis (Scalar "Double" True) True (Scaled (Just 0.0) Nothing Linear))
          Vertical (ChartLegendOptions LegendHidden) (ChartRenderHints True))
        [seriesOf [] [col tpLabel] (col tpMs) [] Nothing (Constant "ms") [] Bar]
        (tracePhases t))
    -- the slowest relation first: the sort is a mark on the Total ms column
    , tabular (simpleTable
        [ withHeader "#" (numCol tqOrder count)
        , withHeader "Relation" (col tqPath)
        , withHeader "Delivery" (col tqDelivery)
        , withHeader "Dialect" (col tqDialect)
        , withHeader "Rows read" (numCol tqRowsRead count)
        , withHeader "Rows" (numCol tqRows count)
        , withHeader "DB ms" (numCol tqDbMs millis)
        , sortDesc (withHeader "Total ms" (numCol tqMs millis))
        , withHeader "Share" (numCol tqShare share) ]
        (traceQueries t))
    , pieChart (pieChartOf (PieSource "Time by relation" "ms" tqPath tqMs
                                      Nothing Nothing Nothing Default millis
                                      (ChartLegendOptions LegendRightTable) (ChartRenderHints True)
                                      (Inline (traceQueries t))))
    , tabular (simpleTable
        [ sortAsc (withHeader "#" (numCol tsOrder count))
        , withHeader "Relation" (col tsPath)
        , withHeader "Bytes" (numCol tsSqlBytes count)
        , withHeader "Setup" (col tsSetup)
        , withHeader "SQL" (col tsSql) ]
        (traceSql t))
    , plainText (TextProps ("Each SQL text is capped at 16 KiB by the server, which then appends " ++
                            "\"-- [ermine: truncated, N more bytes]\"; Bytes is the full length."))
    ]
