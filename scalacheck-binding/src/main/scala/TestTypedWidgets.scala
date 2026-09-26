package com.clarifi.reporting

import com.clarifi.reporting.ermine.json.{ Doc, Write, WriteConfig, Guard }

import scalaz.Id.Id

import org.scalacheck._
import Prop.{ Result => _, _ }

/** WP-37 (tracker/TYPED-COLUMNS.md, D1/D4) for the widgets other than the table:
  * the typed authoring API of `Layout.Widgets.{Chart, AxisChart, PieChart, Scorecard,
  * Drilldown, DrilldownBar, StyleBox, Heading}`.  The wire props are unchanged (D3);
  * a report builds them from a `...Source` record of `Field` slots (`pieChartOf`,
  * `scorecardOf`, `drilldownTableOf`, `drilldownBarOf`, `styleBoxOf`, `headingOf`) or,
  * for a chart's open column lists, from a `Series r` of `Column r` values
  * (`seriesOf`, `simpleSeries`, `axisChartOf`).
  *
  *  - ACCEPTANCE: every typed constructor writes the SAME document, byte for byte,
  *    as the hand-spelled wire props (the document writer, rows included), and the
  *    typed Doc.SalesReport widgets write the bytes the pre-migration dump holds
  *    (scratch-widget-preview/typedcols/before/Doc.SalesReport.1.json, pinned).
  *    An absent `Maybe` slot (`Nothing`) type-checks: its row variable is free and
  *    the partition takes it as the empty row.
  *  - REFUSAL: a slot or series column the relation lacks is a row-partition type
  *    error; two fixed slots given the SAME field are refused by the partition
  *    ("Fields appear twice in row"); each refusal has an accepted twin.
  */
object TestTypedWidgets extends Properties("typed widget columns (WP-37)") {
  private lazy val fixture = ErmineFixture()
  import fixture._

  val wImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Json" -> all, "List" -> all, "Maybe" -> all,
        "Native.List" -> all, "Native.Relation" -> all, "Layout.Doc" -> all,
        "Layout.Widgets.Format" -> all, "Layout.Widgets.Table" -> all,
        "Layout.Widgets.Drilldown" -> all, "Layout.Widgets.Scorecard" -> all,
        "Layout.Widgets.Chart" -> all, "Layout.Widgets.AxisChart" -> all,
        "Layout.Widgets.PieChart" -> all, "Layout.Widgets.StyleBox" -> all,
        "Layout.Widgets.DrilldownBar" -> all,
        // Heading's `title`/`sortColumn`/`total` clash with Scorecard/Table/Headline
        // (Layout/Widgets.e), so it comes in under an alias: `headingOf_H` etc.
        "Layout.Widgets.Heading" -> ((Some("H"), Nil, false): ImportSpec))

  /** Doc.SalesReport's three fields and rows, and a wider relation for the other
    * widgets; `wTarget` and `wNote` are in NO relation (the refusals' missing columns).
    * The rows are listed in the order the dump's server wrote them (APAC first): this
    * in-process writer keeps a literal relation's order, and the widgets under test
    * pass the rows through untouched. */
  val prelude: String = List(
    "field srRegion : String",
    "field srSales : Double",
    "field srDelta : Double",
    "sales : [srRegion, srSales, srDelta]",
    "sales = mkRelation# (toList#",
    "  [ { srRegion = \"APAC\", srSales = 98.25,  srDelta = -0.04 }",
    "  , { srRegion = \"EMEA\", srSales = 120.5,  srDelta = 0.125 }",
    "  , { srRegion = \"AMER\", srSales = 310.75, srDelta = 0.5 }",
    "  ])",
    "field wRegion : String",
    "field wSales : Double",
    "field wDelta : Double",
    "field wColor : String",
    "field wKid : String",
    "field wPar : String",
    "field wPx : Int",
    "field wPy : Int",
    "field wTarget : Double",
    "field wNote : String",
    "wide : [wRegion, wSales, wDelta, wColor, wKid, wPar, wPx, wPy]",
    "wide = mkRelation# (toList#",
    "  [ { wRegion = \"EMEA\", wSales = 1.5, wDelta = 0.25, wColor = \"#ff0000\", wKid = \"e\", wPar = \"\", wPx = 0, wPy = 2 }",
    "  , { wRegion = \"Paris\", wSales = 2.5, wDelta = -0.5, wColor = \"#00ff00\", wKid = \"p\", wPar = \"e\", wPx = 1, wPy = 1 }",
    "  ])",
    "meta0 : ChartMeta",
    "meta0 = simpleMeta \"Sales\" (categoryAxis \"Region\" Default) (valueAxis \"Sales\" (Round False False 1))"
  ).mkString("\n")

  /** The document `e : Node` writes: the writer and scanner the runner uses. */
  private def doc(e: String): String = {
    val rt = defAndEval(prelude + "\ngv : Node\ngv = " + e, "gv", wImps)
    val d = Doc.fromRuntime(rt).fold(err => sys.error(err.report), identity)
    val sb = new java.lang.StringBuilder
    Write.doc[Id](Doc.document(d), sb, WriteConfig(), TestWidgets.cache())(new TestDoc.ListScanner, Guard.id)
    sb.toString
  }

  /** The typed and the hand-spelled wire widget write the same bytes. */
  private def sameDoc(typed: String, wire: String): Prop = secure {
    val a = doc(typed)
    val b = doc(wire)
    ((a ?= b) && (a.contains("\"tag\":\"Widget\"") :| "no widget written")) :|
      ("typed: " + typed + "\n  " + a + "\nwire: " + wire + "\n  " + b)
  }

  /** The refusal text of `e` (after the prelude), or `<accepted: ...>`. */
  private def outcome(e: String): String =
    fixture.run { implicit s =>
      loadStatements(prelude, wImps)
      typeOf(e, wImps)
    } match {
      case scalaparsers.Failure(Some(d), _) => d.toString
      case other                            => "<accepted: " + other + ">"
    }

  /** `bad` is refused with `msg` in the text, and its twin `good` is accepted. */
  private def refused(bad: String, msg: String, good: String): Prop = secure {
    val o = outcome(bad)
    val g = outcome(good)
    ((o contains msg) :| ("expected a refusal containing '" + msg + "' for " + bad + ", got: " + o)) &&
      (g.startsWith("<accepted") :| ("the accepted twin " + good + " was refused: " + g))
  }

  private val pieTail = "Default (Round False False 1) (ChartLegendOptions LegendRightTable) (ChartRenderHints True)"

  // -- ACCEPTANCE --------------------------------------------------------------------------

  property("Doc.SalesReport's typed scorecard, axis chart and pie write the pre-migration dump's bytes") = secure {
    val got = doc(
      "vflow [ scorecard (scorecardOf (ScorecardSource \"Sales by region\" srRegion srSales (Just srDelta) " +
        "(Round False False 1) (Inline sales))), " +
      "axisChart (axisChartOf (ChartMeta \"Sales by region\" " +
        "(ChartAxis \"Region\" \"Region\" Default (Scalar \"String\" False) True (Unscaled [Asc] [])) " +
        "(ChartAxis \"Sales\" \"Sales\" (Round False False 1) (Scalar \"Double\" True) True (Scaled (Just 0.0) Nothing Linear)) " +
        "Vertical (ChartLegendOptions LegendAbove) (ChartRenderHints False)) " +
        "[seriesOf [] [col srRegion] (col srSales) [] Nothing (Constant \"Sales\") [] Bar] sales), " +
      "pieChart (pieChartOf (PieSource \"Share of sales\" \"Sales\" srRegion srSales Nothing Nothing Nothing " +
        pieTail + " (Inline sales))) ]")
    // children 0, 2 and 3 of before/Doc.SalesReport.1.json (the table, child 1, is migration's)
    val want = """{"version":1,"settings":{},"root":{"tag":"VFlow","children":[{"tag":"Widget","name":"scorecard","props":{"title":"Sales by region","cardLabel":"srRegion","cardValue":"srSales","cardDelta":"srDelta","cardFormat":{"tag":"Round","color":false,"negParens":false,"places":1},"cards":{"kind":"inline","columns":[{"name":"srDelta","type":"Double","nullable":false},{"name":"srRegion","type":"String","nullable":false},{"name":"srSales","type":"Double","nullable":false}],"rows":[[-0.04,"APAC",98.25],[0.125,"EMEA",120.5],[0.5,"AMER",310.75]],"rowCount":3}}},{"tag":"Widget","name":"axisChart","props":{"chartMeta":{"chartTitle":"Sales by region","domainAxis":{"axisLabel":"Region","tooltipLabel":"Region","axisFormat":{"tag":"Default","args":[]},"scalarType":{"tag":"Scalar","typeName":"String","typeNumeric":false},"showTicks":true,"constraints":{"tag":"Unscaled","sortOrders":["Asc"],"tickOverrides":[]}},"rangeAxis":{"axisLabel":"Sales","tooltipLabel":"Sales","axisFormat":{"tag":"Round","color":false,"negParens":false,"places":1},"scalarType":{"tag":"Scalar","typeName":"Double","typeNumeric":true},"showTicks":true,"constraints":{"tag":"Scaled","lowerBound":0.0,"displayScale":"Linear"}},"orientation":"Vertical","legendOptions":{"legendLocation":"LegendAbove"},"renderHints":{"enableDataLabels":false}},"chartSeries":[{"seriesColumns":[],"categoryColumns":["srRegion"],"valueColumn":"srSales","extraColumns":[],"seriesFormat":{"tag":"Constant","value":"Sales"},"extraFormats":[],"variant":{"tag":"Bar","args":[]}}],"chartRows":{"kind":"inline","columns":[{"name":"srDelta","type":"Double","nullable":false},{"name":"srRegion","type":"String","nullable":false},{"name":"srSales","type":"Double","nullable":false}],"rows":[[-0.04,"APAC",98.25],[0.125,"EMEA",120.5],[0.5,"AMER",310.75]],"rowCount":3}}},{"tag":"Widget","name":"pieChart","props":{"pieTitle":"Share of sales","seriesName":"Sales","pieLabelColumn":"srRegion","pieValueColumn":"srSales","pieLabelFormat":{"tag":"Default","args":[]},"pieValueFormat":{"tag":"Round","color":false,"negParens":false,"places":1},"pieLegend":{"legendLocation":"LegendRightTable"},"pieHints":{"enableDataLabels":true},"pieRows":{"kind":"inline","columns":[{"name":"srDelta","type":"Double","nullable":false},{"name":"srRegion","type":"String","nullable":false},{"name":"srSales","type":"Double","nullable":false}],"rows":[[-0.04,"APAC",98.25],[0.125,"EMEA",120.5],[0.5,"AMER",310.75]],"rowCount":3}}}]}}"""
    (got ?= want)
  }

  property("pie: every slot filled (drilldownPieChart) = the wire props") =
    sameDoc("drilldownPieChart (pieChartOf (PieSource \"T\" \"S\" wRegion wSales (Just wColor) (Just wKid) (Just wPar) " +
              pieTail + " (Inline wide)))",
            "drilldownPieChart (PieChartProps \"T\" \"S\" \"wRegion\" \"wSales\" (Just \"wColor\") (Just \"wKid\") (Just \"wPar\") " +
              pieTail + " (Inline wide))")

  property("pie: optional slots absent (Nothing) type-check and write no key") =
    sameDoc("pieChart (pieChartOf (PieSource \"T\" \"S\" wRegion wSales Nothing (Just wKid) Nothing " + pieTail + " (Inline wide)))",
            "pieChart (PieChartProps \"T\" \"S\" \"wRegion\" \"wSales\" Nothing (Just \"wKid\") Nothing " + pieTail + " (Inline wide))")

  property("scorecard: scorecardOf without a delta, and simpleScorecard = the wire props") =
    sameDoc("scorecard (scorecardOf (ScorecardSource \"T\" wRegion wSales Nothing Default (Inline wide)))",
            "scorecard (ScorecardProps \"T\" \"wRegion\" \"wSales\" Nothing Default (Inline wide))") &&
    sameDoc("scorecard (simpleScorecard \"T\" wRegion wSales Default (Inline wide))",
            "scorecard (ScorecardProps \"T\" \"wRegion\" \"wSales\" Nothing Default (Inline wide))")

  property("axis chart: seriesOf with every slot, several series, simpleSeries/simpleAxisChart = the wire props") =
    sameDoc("axisChart (axisChartOf meta0 [seriesOf [col wRegion] [col wPar, col wKid] (col wSales) [col wDelta, col wPx] " +
              "(Just (col wColor)) Default [Verbatim, Default] (Bubble \"z\"), simpleSeries (col wRegion) (col wDelta) Line] wide)",
            "axisChart (AxisChartProps meta0 [ChartSeries [\"wRegion\"] [\"wPar\", \"wKid\"] \"wSales\" [\"wDelta\", \"wPx\"] " +
              "(Just \"wColor\") Default [Verbatim, Default] (Bubble \"z\"), " +
              "ChartSeries [] [\"wRegion\"] \"wDelta\" [] Nothing Default [] Line] wide)") &&
    sameDoc("axisChart (simpleAxisChart meta0 (simpleSeries (withHeader \"ignored\" (col wRegion)) (col wSales) Bar) wide)",
            "axisChart (AxisChartProps meta0 [ChartSeries [] [\"wRegion\"] \"wSales\" [] Nothing Default [] Bar] wide)")

  property("drilldown table: columns lower as simpleTable does (sort marks too), the roles by name") =
    sameDoc("drilldownTable (drilldownTableOf (DrilldownSource [withHeader \"Region\" (col wRegion), sortDesc (numCol wSales Verbatim)] " +
              "wPar wKid wRegion wide))",
            "drilldownTable (DrilldownTableProps [TableColumn \"wRegion\" \"Region\" Default AlignLeft OtherColumn, " +
              "TableColumn \"wSales\" \"wSales\" Verbatim AlignRight NumberColumn] \"wPar\" \"wKid\" \"wRegion\" " +
              "[ColumnSort 1 True] True True wide)")

  property("drilldown bar = the wire props") =
    sameDoc("drilldownBar (drilldownBarOf (DrilldownBarSource meta0 (simpleSeries (col wRegion) (col wSales) Bar) wPar wKid wide))",
            "drilldownBar (DrilldownBarProps meta0 (ChartSeries [] [\"wRegion\"] \"wSales\" [] Nothing Default [] Bar) \"wPar\" \"wKid\" wide)")

  property("style box = the wire props") =
    sameDoc("styleBox (styleBoxOf (StyleBoxSource \"X\" \"Y\" wSales \"Sum\" Verbatim wPx wPy [\"a\", \"b\", \"c\"] [\"d\", \"e\", \"f\"] " +
              "True [(0.0, 1.0)] [(1.0, 2.5)] (Inline wide)))",
            "styleBox (StyleBoxProps \"X\" \"Y\" \"wSales\" \"Sum\" Verbatim \"wPx\" \"wPy\" [\"a\", \"b\", \"c\"] [\"d\", \"e\", \"f\"] " +
              "True [(0.0, 1.0)] [(1.0, 2.5)] (Inline wide))")

  property("heading: the sort column's name, checked against the relation it is over") =
    sameDoc("heading_H (headingOf_H (HeadingSource_H \"Sales\" (col wSales) 3 4350.75 wide))",
            "heading_H (HeadingProps_H \"Sales\" \"wSales\" 3 4350.75)")

  // -- REFUSAL -----------------------------------------------------------------------------

  private val missing = "Row partitions are unsatisfiable at field 'Test.wTarget'"

  property("refused: a pie slot the relation lacks; the same field in two pie slots (fixed and Maybe)") =
    refused("pieChartOf (PieSource \"T\" \"S\" wRegion wTarget Nothing Nothing Nothing " + pieTail + " (Inline wide))", missing,
            "pieChartOf (PieSource \"T\" \"S\" wRegion wSales Nothing Nothing Nothing " + pieTail + " (Inline wide))") &&
    refused("pieChartOf (PieSource \"T\" \"S\" wRegion wRegion Nothing Nothing Nothing " + pieTail + " (Inline wide))",
            "Fields appear twice in row: Test.wRegion",
            "pieChartOf (PieSource \"T\" \"S\" wRegion wSales Nothing Nothing Nothing " + pieTail + " (Inline wide))") &&
    refused("pieChartOf (PieSource \"T\" \"S\" wRegion wSales Nothing (Just wKid) (Just wKid) " + pieTail + " (Inline wide))",
            "Fields appear twice in row: Test.wKid",
            "pieChartOf (PieSource \"T\" \"S\" wRegion wSales Nothing (Just wKid) (Just wPar) " + pieTail + " (Inline wide))") &&
    refused("pieChartOf (PieSource \"T\" \"S\" wRegion wSales (Just wNote) Nothing Nothing " + pieTail + " (Inline wide))",
            "Row partitions are unsatisfiable at field 'Test.wNote'",
            "pieChartOf (PieSource \"T\" \"S\" wRegion wSales (Just wColor) Nothing Nothing " + pieTail + " (Inline wide))")

  property("refused: a scorecard slot the relation lacks; label = value; delta = value") =
    refused("scorecardOf (ScorecardSource \"T\" wRegion wTarget Nothing Default (Inline wide))", missing,
            "scorecardOf (ScorecardSource \"T\" wRegion wSales Nothing Default (Inline wide))") &&
    refused("scorecardOf (ScorecardSource \"T\" wSales wSales Nothing Default (Inline wide))",
            "Fields appear twice in row: Test.wSales",
            "scorecardOf (ScorecardSource \"T\" wRegion wSales Nothing Default (Inline wide))") &&
    refused("scorecardOf (ScorecardSource \"T\" wRegion wSales (Just wSales) Default (Inline wide))",
            "Fields appear twice in row: Test.wSales",
            "scorecardOf (ScorecardSource \"T\" wRegion wSales (Just wDelta) Default (Inline wide))")

  property("refused: a series column the chart's relation lacks (value, category, colour)") =
    refused("axisChartOf meta0 [simpleSeries (col wRegion) (col wTarget) Bar] wide", missing,
            "axisChartOf meta0 [simpleSeries (col wRegion) (col wSales) Bar] wide") &&
    refused("axisChartOf meta0 [seriesOf [] [col wTarget] (col wSales) [] Nothing Default [] Bar] wide", missing,
            "axisChartOf meta0 [seriesOf [] [col wRegion] (col wSales) [] Nothing Default [] Bar] wide") &&
    refused("axisChartOf meta0 [seriesOf [] [col wRegion] (col wSales) [] (Just (col wTarget)) Default [] Bar] wide", missing,
            "axisChartOf meta0 [seriesOf [] [col wRegion] (col wSales) [] (Just (col wColor)) Default [] Bar] wide")

  property("refused: drilldown table parent = child; a label or a displayed column the relation lacks") =
    refused("drilldownTableOf (DrilldownSource [col wRegion] wKid wKid wRegion wide)",
            "Fields appear twice in row: Test.wKid",
            "drilldownTableOf (DrilldownSource [col wRegion] wPar wKid wRegion wide)") &&
    refused("drilldownTableOf (DrilldownSource [col wRegion] wPar wKid wTarget wide)", missing,
            "drilldownTableOf (DrilldownSource [col wRegion] wPar wKid wRegion wide)") &&
    refused("drilldownTableOf (DrilldownSource [col wTarget] wPar wKid wRegion wide)", missing,
            "drilldownTableOf (DrilldownSource [col wSales] wPar wKid wRegion wide)")

  property("refused: drilldown bar parent = child; a parent the relation lacks") =
    refused("drilldownBarOf (DrilldownBarSource meta0 (simpleSeries (col wRegion) (col wSales) Bar) wPar wPar wide)",
            "Fields appear twice in row: Test.wPar",
            "drilldownBarOf (DrilldownBarSource meta0 (simpleSeries (col wRegion) (col wSales) Bar) wPar wKid wide)") &&
    refused("drilldownBarOf (DrilldownBarSource meta0 (simpleSeries (col wRegion) (col wTarget) Bar) wPar wKid wide)", missing,
            "drilldownBarOf (DrilldownBarSource meta0 (simpleSeries (col wRegion) (col wSales) Bar) wPar wKid wide)")

  property("refused: style box x position = y position; an aggregate the relation lacks") =
    refused("styleBoxOf (StyleBoxSource \"X\" \"Y\" wSales \"Sum\" Default wPx wPx [] [] True [] [] (Inline wide))",
            "Fields appear twice in row: Test.wPx",
            "styleBoxOf (StyleBoxSource \"X\" \"Y\" wSales \"Sum\" Default wPx wPy [] [] True [] [] (Inline wide))") &&
    refused("styleBoxOf (StyleBoxSource \"X\" \"Y\" wTarget \"Sum\" Default wPx wPy [] [] True [] [] (Inline wide))", missing,
            "styleBoxOf (StyleBoxSource \"X\" \"Y\" wDelta \"Sum\" Default wPx wPy [] [] True [] [] (Inline wide))")

  property("refused: a heading sort column the relation it is over lacks") =
    refused("headingOf_H (HeadingSource_H \"Sales\" (col wTarget) 3 1.0 wide)", missing,
            "headingOf_H (HeadingSource_H \"Sales\" (col wDelta) 3 1.0 wide)")
}
