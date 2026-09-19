package com.clarifi.reporting

import com.clarifi.reporting.ermine.json.{ Doc, Write, WriteConfig, MemoryPlanCache,
                                           Delivery, Schema, Validate, Wire, Guard }
import com.clarifi.reporting.ermine.session.Session

import scalaz.Id.Id

import org.scalacheck._
import Prop.{ Result => _, _ }
import argonaut.{ Json, Parse }

import scala.collection.mutable.ListBuffer

/** Stage J3d (tracker/json-stage3/brief-J3d-client.md): the widget prop types
  * (the modules under `modules/Layout/Widgets/`) and the documents the client is
  * handed.
  *
  * Property (a) is the DOCUMENT half of the contract, on the Scala side: random
  * values of every prop type, written as generated Ermine source over random
  * literal relations, go through `Write.doc` and must validate against the schema
  * `bin/ermine-schema` exports for that prop type -- the same schema
  * `client/scripts/generate.sh` turns into the zod the dispatcher uses.  The
  * cross-language half (b) is `client/scripts/check-corpus.sh`, whose corpus this
  * file writes (`WidgetCorpus`).
  *
  * Anti-vacuity: every case also mutates one leaf of the props and requires the
  * schema to REJECT the mutant, and the fixed-sample properties assert that every
  * widget, every CellFormat constructor and every delivery outcome occurred.
  */
object TestWidgets extends Properties("widget prop types (J3d)") {
  private lazy val fixture = ErmineFixture()
  import fixture.{ session, all, ImportSpec, supply, con }

  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Json" -> all, "List" -> all, "Maybe" -> all,
        "Layout.Doc" -> all, "Layout.Widgets.Format" -> all, "Layout.Widgets.Table" -> all,
        "Layout.Widgets.Drilldown" -> all, "Layout.Widgets.Scorecard" -> all,
        "Layout.Widgets.Headline" -> all, "Layout.Widgets.Crosstab" -> all,
        "Layout.Widgets.Chart" -> all, "Layout.Widgets.AxisChart" -> all,
        "Layout.Widgets.PieChart" -> all, "Layout.Widgets.StyleBox" -> all,
        "Layout.Widgets.DrilldownBar" -> all,
        "Native.List" -> all)

  // =====================================================================
  // generated Ermine SOURCE for a props value

  /** The relation columns a generated literal relation may have.  Held to the
    * types a `field` declaration and an Ermine literal can both spell. */
  private val relFieldPool: List[(String, String)] =
    List(("wfName", "String"), ("wfValue", "Double"), ("wfCount", "Int"),
         ("wfFlag", "Bool"), ("wfParent", "String"), ("wfChild", "String"),
         // J3e: a css colour column for the chart adapters.  Its Ermine type is
         // String; "Color" only selects the literal generator, which mints both
         // well-formed `#rrggbb` and junk, so the adapters' "#RRGGBB or null"
         // invariant is exercised on both sides.
         ("wfColor", "Color"))

  /** The Ermine type a pool entry declares (`Color` is a String column). */
  private def ermineType(ty: String): String = if (ty == "Color") "String" else ty

  private def litFor(ty: String): Gen[String] = ty match {
    case "Int"    => Gen.choose(0, 99999).map(_.toString)
    case "String" => Gen.alphaNumStr.map(s => "\"" + s.take(6) + "\"")
    case "Bool"   => Gen.oneOf("True", "False")
    case "Double" => Gen.choose(0, 99999).map(n => (n / 8.0).toString)
    case "Color"  => Gen.frequency(
                       (5, Gen.listOfN(6, Gen.oneOf("0123456789abcdef".toList))
                             .map(cs => "\"#" + cs.mkString + "\"")),
                       (1, Gen.oneOf("\"red\"", "\"\"", "\"#12345\"")))
  }

  /** A literal relation: its `field` declarations, the column names, the source. */
  final case class RelSrc(decls: List[String], columns: List[String], expr: String)

  private val relSrc: Gen[RelSrc] =
    for {
      k    <- Gen.choose(2, relFieldPool.length)
      fs   <- TestSchema.pickN(k, relFieldPool).map(_.sortBy(_._1))
      // at least one row: `mkRelation# (toList# [])` carries no header, and
      // Doc.fromRuntime refuses a header-less empty relation (it would need a
      // static hint).  The empty-relation case is covered by the client's own
      // tests, which hand-write the wire object.
      n    <- Gen.choose(1, 6)
      recs <- Gen.listOfN(n, Gen.sequence[List[String], String](
                fs.map { case (f, t) => litFor(t).map(f + " = " + _) }).map(_.mkString("{ ", ", ", " }")))
    } yield RelSrc(fs.map { case (f, t) => "field " + f + " : " + ermineType(t) },
                   fs.map(_._1),
                   "(mkRelation# (toList# [" + recs.mkString(", ") + "]))")

  /** The style box aggregates on two SMALL integer position columns (the grid is
    * 3x3), so it gets its own relation rather than a slice of the pool. */
  private val posRelSrc: Gen[RelSrc] =
    for {
      n    <- Gen.choose(1, 8)
      recs <- Gen.listOfN(n, for {
                x <- Gen.choose(0, 3)         // 3 is out of the grid on purpose
                y <- Gen.choose(0, 3)
                a <- Gen.choose(0, 9999)
                s <- Gen.alphaNumStr
              } yield "{ sbAmount = " + (a / 4.0) + ", sbLabel = \"" + s.take(4) +
                      "\", sbX = " + x + ", sbY = " + y + " }")
    } yield RelSrc(List("field sbAmount : Double", "field sbLabel : String",
                        "field sbX : Int", "field sbY : Int"),
                   List("sbAmount", "sbLabel", "sbX", "sbY"),
                   "(mkRelation# (toList# [" + recs.mkString(", ") + "]))")

  private val thresholdSrc: Gen[String] = Gen.oneOf(
    Gen.choose(0, 999).map(n => "(TNum " + (n / 4.0) + ")"),
    Gen.alphaNumStr.map(s => "(TStr \"" + s.take(5) + "\")"),
    Gen.oneOf("(TBool True)", "(TBool False)"))

  private def conditionSrc(depth: Int): Gen[String] = {
    val leaf = thresholdSrc.flatMap(t =>
      Gen.oneOf("Gt", "Lt", "Eq", "Gte", "Lte").map(c => "(" + c + " " + t + ")"))
    if (depth <= 0) leaf
    else Gen.frequency((4, leaf),
      (1, Gen.zip(conditionSrc(depth - 1), conditionSrc(depth - 1)).map {
        case (a, b) => "(And (" + a + ", " + b + "))" }))
  }

  private def rgbSrc: Gen[String] =
    Gen.zip(Gen.choose(0, 255), Gen.choose(0, 255), Gen.choose(0, 255)).map {
      case (r, g, b) => "(RGB " + r + " " + g + " " + b + ")" }

  /** One source expression per CellFormat constructor, tagged with the
    * constructor name so a coverage assertion can see what was generated. */
  def cellFormatSrc(depth: Int): Gen[(String, List[String])] = {
    val bools = Gen.oneOf("True", "False")
    val flat: List[Gen[(String, List[String])]] = List(
      Gen.const(("Default", List("Default"))),
      Gen.const(("Verbatim", List("Verbatim"))),
      Gen.const(("DateRange", List("DateRange"))),
      Gen.alphaNumStr.map(s => ("(Constant \"" + s.take(6) + "\")", List("Constant"))),
      for { c <- bools; p <- bools; n <- Gen.choose(0, 6); pad <- bools }
        yield ("(Percentage " + c + " " + p + " " + n + " " + pad + ")", List("Percentage")),
      for { c <- bools; p <- bools; s <- Gen.oneOf("$", "€", "USD"); n <- Gen.choose(0, 4) }
        yield ("(Currency " + c + " " + p + " \"" + s + "\" " + n + ")", List("Currency")),
      for { c <- bools; p <- bools; n <- Gen.choose(0, 6) }
        yield ("(Round " + c + " " + p + " " + n + ")", List("Round")),
      for { c <- bools; p <- bools; n <- Gen.choose(0, 6) }
        yield ("(IntegralRound " + c + " " + p + " " + n + ")", List("IntegralRound")),
      Gen.choose(1, 20).map(n => ("(Truncate " + n + ")", List("Truncate"))),
      Gen.choose(0, 3).flatMap(k => Gen.listOfN(k, Gen.zip(Gen.alphaNumStr, Gen.alphaNumStr))).map { ps =>
        ("(Alias [" + ps.map { case (a, b) => "(\"" + a.take(4) + "\", \"" + b.take(4) + "\")" }.mkString(", ") + "])",
         List("Alias")) })
    if (depth <= 0) Gen.oneOf(flat).flatMap(identity)
    else {
      def inner = cellFormatSrc(depth - 1)
      Gen.frequency(
        (6, Gen.oneOf(flat).flatMap(identity)),
        (1, inner.map { case (s, t) => ("(Markdown " + s + ")", "Markdown" :: t) }),
        (1, inner.map { case (s, t) => ("(Pr1 " + s + ")", "Pr1" :: t) }),
        (1, inner.map { case (s, t) => ("(Pr2 " + s + ")", "Pr2" :: t) }),
        (1, for { c <- conditionSrc(1); a <- inner; b <- inner }
              yield ("(Conditional " + c + " " + a._1 + " " + b._1 + ")",
                     "Conditional" :: a._2 ++ b._2)),
        (1, for { bg <- rgbSrc; fg <- rgbSrc; a <- inner }
              yield ("(Color " + bg + " " + fg + " " + a._1 + ")", "Color" :: a._2)))
    }
  }

  private def alignSrc: Gen[String] = Gen.oneOf("AlignLeft", "AlignRight")
  private def kindSrc: Gen[String] = Gen.oneOf("NumberColumn", "DateColumn", "OtherColumn")

  private def columnSrc(name: String): Gen[(String, List[String])] =
    for {
      h <- Gen.alphaNumStr
      f <- cellFormatSrc(2)
      a <- alignSrc
      k <- kindSrc
    } yield ("(TableColumn \"" + name + "\" \"" + (if (h.isEmpty) name else h.take(8)) + "\" " +
             f._1 + " " + a + " " + k + ")", f._2)

  private def columnsSrc(rel: RelSrc): Gen[(String, List[String])] =
    for {
      k    <- Gen.choose(1, rel.columns.length)
      // a displayed column may also name a column the relation does not have
      cols <- Gen.listOfN(k, Gen.frequency((9, Gen.oneOf(rel.columns)), (1, Gen.const("wfAbsent"))))
      srcs <- Gen.sequence[List[(String, List[String])], (String, List[String])](cols.map(columnSrc))
    } yield (srcs.map(_._1).mkString("[", ", ", "]"), srcs.flatMap(_._2))

  private def sortsSrc(n: Int): Gen[String] =
    Gen.choose(0, math.min(2, n)).flatMap(k =>
      Gen.listOfN(k, Gen.zip(Gen.choose(0, math.max(0, n - 1)), Gen.oneOf("True", "False")))
        .map(_.map { case (i, d) => "(ColumnSort " + i + " " + d + ")" }.mkString("[", ", ", "]")))

  /** A generated widget node: the `field` declarations it needs, the expression,
    * the registry name, the schema its props must validate against, and the
    * CellFormat constructors that occurred. */
  final case class WidgetSrc(decls: List[String], expr: String, widget: String,
                             module: String, propsType: String, tags: List[String])

  private val bools = Gen.oneOf("True", "False")

  val tableSrc: Gen[WidgetSrc] =
    for {
      r  <- relSrc
      cs <- columnsSrc(r)
      nc = cs._1.split("\\(TableColumn").length - 1
      rg <- Gen.frequency((2, Gen.const("Nothing")), (1, Gen.choose(0, math.max(0, nc - 1)).map(i => "(Just " + i + ")")))
      so <- sortsSrc(nc)
      pg <- bools
      sc <- bools
    } yield
      // `TableProps.rows` is declared `[..r]`, a BARE relation: the request's
      // default delivery decides, and `Inline`/`Deferred` are kind errors here
      // (they take a row and build a different type).  The explicit wrapper is
      // exercised by the scorecard, whose `cards` is `Inline r`.
      WidgetSrc(r.decls,
                "(tabular (TableProps " + cs._1 + " " + rg + " " + so + " " + pg + " " + sc + " " + r.expr + "))",
                "table", "Layout.Widgets.Table", "TableProps", "wrap-bare" :: cs._2)

  val drilldownSrc: Gen[WidgetSrc] =
    for {
      r  <- relSrc
      cs <- columnsSrc(r)
      nc = cs._1.split("\\(TableColumn").length - 1
      so <- sortsSrc(nc)
      pg <- bools
      sc <- bools
      par <- Gen.oneOf(r.columns)
      chi <- Gen.oneOf(r.columns)
      lbl <- Gen.oneOf(r.columns)
    } yield WidgetSrc(r.decls,
      "(drilldownTable (DrilldownTableProps " + cs._1 + " \"" + par + "\" \"" + chi + "\" \"" + lbl +
        "\" " + so + " " + pg + " " + sc + " " + r.expr + "))",
      "drilldownTable", "Layout.Widgets.Drilldown", "DrilldownTableProps", "wrap-bare" :: cs._2)

  val scorecardSrc: Gen[WidgetSrc] =
    for {
      r   <- relSrc
      ttl <- Gen.alphaNumStr
      lbl <- Gen.oneOf(r.columns)
      vl  <- Gen.oneOf(r.columns)
      dl  <- Gen.frequency((1, Gen.const("Nothing")), (2, Gen.oneOf(r.columns).map(c => "(Just \"" + c + "\")")))
      f   <- cellFormatSrc(2)
    } yield WidgetSrc(r.decls,
      "(scorecard (ScorecardProps \"" + ttl.take(8) + "\" \"" + lbl + "\" \"" + vl + "\" " + dl + " " +
        f._1 + " (Inline " + r.expr + ")))",
      "scorecard", "Layout.Widgets.Scorecard", "ScorecardProps", "wrap-Inline" :: f._2)

  /** J3g: the headline.  Its props carry NO relation -- `headlineOf` scanned one
    * in Ermine and only the three numbers travel -- so this generator is the
    * simplest one here: the widget is a record of two strings, three numbers and
    * a format. */
  val headlineSrc: Gen[WidgetSrc] =
    for {
      t   <- Gen.alphaNumStr
      sc  <- Gen.alphaNumStr
      n   <- Gen.choose(0, 9999)
      // non-negative, like every other literal here: a bare `-1.5` argument is
      // parsed as the operator `-` ("unknown operator -"), and the negative
      // cases are covered where they belong, in TestRunner's (fxl-headline)
      // where the numbers sit inside a record literal
      tot <- Gen.choose(0, 99999).map(_ / 8.0)
      max <- Gen.choose(0, 99999).map(_ / 8.0)
      f   <- cellFormatSrc(2)
    } yield WidgetSrc(List(),
      "(headline (HeadlineProps \"" + t.take(8) + "\" \"" + sc.take(8) + "\" " + n + " " + tot + " " +
        max + " " + f._1 + "))",
      "headline", "Layout.Widgets.Headline", "HeadlineProps", "no-relation" :: f._2)

  /** J3i: the crosstab.  Like the headline its props carry NO relation --
    * `crosstabOf` scanned one server-side and only the matrix travels -- and
    * unlike every other widget here a cell may be ABSENT: an Ermine `Nothing`
    * INSIDE a list is `null` on the wire, not a dropped key (the encoder's
    * omit-the-key rule is for a named field).  The totals are computed from
    * the generated cells, so a generated document is a crosstab that adds up.
    *
    * Non-negative literals, for `headlineSrc`'s reason: a bare `-1.5` as an
    * argument parses as the operator `-`.  The signed cases live in
    * TestRunner's (fxc-1), where the numbers sit inside a record literal. */
  val crosstabSrc: Gen[WidgetSrc] =
    for {
      t    <- Gen.alphaNumStr
      rh   <- Gen.alphaNumStr
      ch   <- Gen.alphaNumStr
      nr   <- Gen.choose(0, 3)
      nc   <- Gen.choose(0, 3)
      rls  <- Gen.listOfN(nr, Gen.alphaNumStr.map(_.take(4)))
      cls  <- Gen.listOfN(nc, Gen.alphaNumStr.map(_.take(4)))
      cs   <- Gen.listOfN(nr, Gen.listOfN(nc, Gen.frequency(
                (1, Gen.const(None: Option[Double])),
                (3, Gen.choose(0, 99999).map(v => Some(v / 8.0))))))
      f    <- cellFormatSrc(2)
    } yield {
      // distinct labels, as `crosstabOf` produces them
      val rowLabels = rls.zipWithIndex.map { case (l, i) => "r" + i + l }
      val colLabels = cls.zipWithIndex.map { case (l, i) => "c" + i + l }
      def lits(xs: List[String]) = xs.map(x => "\"" + x + "\"").mkString("[", ", ", "]")
      val cells = cs.map(row => row.map {
        case None    => "Nothing"
        case Some(v) => "(Just " + v + ")"
      }.mkString("[", ", ", "]")).mkString("[", ", ", "]")
      val rowTotals = cs.map(_.flatten.sum)
      val colTotals = (0 until nc).toList.map(j => cs.flatMap(_.lift(j).flatten).sum)
      val gap = cs.exists(_.exists(_.isEmpty))
      WidgetSrc(List(),
        "(crosstab (CrosstabProps \"" + t.take(8) + "\" \"" + rh.take(8) + "\" \"" + ch.take(8) + "\" " +
          lits(rowLabels) + " " + lits(colLabels) + " " + cells + " " +
          rowTotals.mkString("[", ", ", "]") + " " + colTotals.mkString("[", ", ", "]") + " " +
          rowTotals.sum + " " + f._1 + "))",
        "crosstab", "Layout.Widgets.Crosstab", "CrosstabProps",
        "no-relation" :: (if (gap) "crosstab-gap" else "crosstab-full") :: f._2)
    }

  // =====================================================================
  // J3e: the chart and style-box generators

  private def scalarTypeSrc(depth: Int): Gen[String] = {
    val leaf = Gen.zip(Gen.oneOf("String", "Double", "Int", "Date"), bools)
                  .map { case (n, num) => "(Scalar \"" + n + "\" " + num + ")" }
    if (depth <= 0) leaf
    else Gen.frequency((5, leaf),
      (1, Gen.choose(1, 3).flatMap(k => Gen.listOfN(k, scalarTypeSrc(depth - 1)))
            .map(ts => "(Compound [" + ts.mkString(", ") + "])")))
  }

  private def maybeDouble: Gen[String] =
    Gen.frequency((1, Gen.const("Nothing")),
                  (2, Gen.choose(0, 9999).map(n => "(Just " + (n / 16.0) + ")")))

  /** An axis.  `nCats` is how many category components the domain has: the
    * legacy `sortByCategory` compares that many, so the sort list is generated to
    * match (categoryOrdering, ermine-htmlwriter.js:1589-1601). */
  private def axisSrc(nCats: Int): Gen[(String, List[String])] =
    for {
      lbl <- Gen.alphaNumStr
      tip <- Gen.alphaNumStr
      f   <- cellFormatSrc(2)
      st  <- scalarTypeSrc(1)
      tk  <- bools
      cs  <- Gen.frequency(
               (1, for { lo <- maybeDouble; hi <- maybeDouble; sc <- Gen.oneOf("Linear", "Logarithmic") }
                     yield ("(Scaled " + lo + " " + hi + " " + sc + ")", List("axis-scaled"))),
               (1, for {
                     ds <- Gen.listOfN(math.max(1, nCats), Gen.oneOf("Asc", "Desc"))
                     k  <- Gen.choose(0, 2)
                     ov <- Gen.listOfN(k, Gen.zip(Gen.alphaNumStr, Gen.alphaNumStr))
                   } yield ("(Unscaled [" + ds.mkString(", ") + "] [" +
                            ov.map { case (a, b) => "(\"" + a.take(3) + "\", \"" + b.take(3) + "\")" }.mkString(", ") +
                            "])", List("axis-unscaled"))))
    } yield ("(ChartAxis \"" + lbl.take(6) + "\" \"" + tip.take(6) + "\" " + f._1 + " " + st + " " +
             tk + " " + cs._1 + ")", f._2 ++ cs._2)

  private val legendSrc: Gen[String] =
    Gen.oneOf("LegendDefault", "LegendAbove", "LegendOverlay", "LegendRightOverlay",
              "LegendRightNotOverlay", "LegendRightTable", "LegendHidden")
      .map(l => "(ChartLegendOptions " + l + ")")

  private def metaSrc(nCats: Int): Gen[(String, List[String])] =
    for {
      t  <- Gen.alphaNumStr
      d  <- axisSrc(nCats)
      r  <- axisSrc(1)
      or <- Gen.oneOf("Vertical", "Horizontal")
      lg <- legendSrc
      dl <- bools
    } yield ("(ChartMeta \"" + t.take(6) + "\" " + d._1 + " " + r._1 + " " + or + " " + lg +
             " (ChartRenderHints " + dl + "))", d._2 ++ r._2)

  private val variantSrc: Gen[(String, List[String])] = Gen.oneOf(
    List("Line", "Bar", "Step", "Scatter", "StackedBar", "StackedArea", "BoxAndWhiskers")
      .map(v => Gen.const((v, List("variant-" + v)))) :+
      Gen.alphaNumStr.map(z => ("(Bubble \"" + z.take(4) + "\")", List("variant-Bubble")))
  ).flatMap(identity)

  /** One ChartSeries over a generated relation.  Returns the source, the number
    * of category components (the meta's sort list must match it) and the tags. */
  private def seriesSrc(rel: RelSrc): Gen[(String, Int, List[String])] =
    for {
      ns   <- Gen.choose(0, 2)
      ss   <- Gen.listOfN(ns, Gen.oneOf(rel.columns))
      nc   <- Gen.choose(1, 2)
      cs   <- Gen.listOfN(nc, Gen.oneOf(rel.columns))
      // a series column naming a column the relation does not have is allowed
      v    <- Gen.frequency((9, Gen.oneOf(rel.columns)), (1, Gen.const("wfAbsent")))
      ne   <- Gen.choose(0, 2)
      es   <- Gen.listOfN(ne, Gen.oneOf(rel.columns))
      col  <- Gen.frequency((2, Gen.const("Nothing")),
                            (3, Gen.oneOf(rel.columns).map(c => "(Just \"" + c + "\")")))
      sf   <- cellFormatSrc(1)
      efs  <- Gen.listOfN(es.length, cellFormatSrc(1))
      va   <- variantSrc
    } yield ("(ChartSeries [" + ss.map("\"" + _ + "\"").mkString(", ") + "] [" +
             cs.map("\"" + _ + "\"").mkString(", ") + "] \"" + v + "\" [" +
             es.map("\"" + _ + "\"").mkString(", ") + "] " + col + " " + sf._1 + " [" +
             efs.map(_._1).mkString(", ") + "] " + va._1 + ")",
             cs.length,
             sf._2 ++ efs.flatMap(_._2) ++ va._2 ++
               (if (col == "Nothing") List("color-absent") else List("color-column")))

  val axisChartSrc: Gen[WidgetSrc] =
    for {
      r  <- relSrc
      k  <- Gen.choose(1, 2)
      ss <- Gen.listOfN(k, seriesSrc(r))
      m  <- metaSrc(ss.map(_._2).max)
    } yield WidgetSrc(r.decls,
      "(axisChart (AxisChartProps " + m._1 + " [" + ss.map(_._1).mkString(", ") + "] " + r.expr + "))",
      "axisChart", "Layout.Widgets.AxisChart", "AxisChartProps",
      "wrap-bare" :: m._2 ++ ss.flatMap(_._3))

  val drilldownBarSrc: Gen[WidgetSrc] =
    for {
      r   <- relSrc
      s   <- seriesSrc(r)
      m   <- metaSrc(s._2)
      par <- Gen.oneOf(r.columns)
      chi <- Gen.oneOf(r.columns)
    } yield WidgetSrc(r.decls,
      "(drilldownBar (DrilldownBarProps " + m._1 + " " + s._1 + " \"" + par + "\" \"" + chi + "\" " +
        r.expr + "))",
      "drilldownBar", "Layout.Widgets.DrilldownBar", "DrilldownBarProps",
      "wrap-bare" :: m._2 ++ s._3)

  /** Both pie registry names come off the same props type. */
  private def pieSrcFor(ctor: String, name: String): Gen[WidgetSrc] =
    for {
      r    <- relSrc
      ttl  <- Gen.alphaNumStr
      sn   <- Gen.alphaNumStr
      lbl  <- Gen.oneOf(r.columns)
      vl   <- Gen.frequency((9, Gen.oneOf(r.columns)), (1, Gen.const("wfAbsent")))
      col  <- Gen.frequency((2, Gen.const("Nothing")),
                            (3, Gen.oneOf(r.columns).map(c => "(Just \"" + c + "\")")))
      dd   <- Gen.oneOf(true, false)
      chi  <- Gen.oneOf(r.columns)
      par  <- Gen.oneOf(r.columns)
      lf   <- cellFormatSrc(1)
      vf   <- cellFormatSrc(1)
      lg   <- legendSrc
      dl   <- bools
    } yield WidgetSrc(r.decls,
      "(" + ctor + " (PieChartProps \"" + ttl.take(6) + "\" \"" + sn.take(6) + "\" \"" + lbl + "\" \"" +
        vl + "\" " + col + " " +
        (if (dd) "(Just \"" + chi + "\") (Just \"" + par + "\") " else "Nothing Nothing ") +
        lf._1 + " " + vf._1 + " " + lg + " (ChartRenderHints " + dl + ") (Inline " + r.expr + ")))",
      name, "Layout.Widgets.PieChart", "PieChartProps",
      "wrap-Inline" :: (if (dd) "pie-drilldown" else "pie-flat") ::
        (if (col == "Nothing") "color-absent" else "color-column") :: lf._2 ++ vf._2)

  val pieSrc: Gen[WidgetSrc] = pieSrcFor("pieChart", "pieChart")
  val drilldownPieSrc: Gen[WidgetSrc] = pieSrcFor("drilldownPieChart", "drilldownPieChart")

  val styleBoxSrc: Gen[WidgetSrc] =
    for {
      r    <- posRelSrc
      xt   <- Gen.alphaNumStr
      yt   <- Gen.alphaNumStr
      at   <- Gen.alphaNumStr
      af   <- cellFormatSrc(1)
      rl   <- Gen.listOfN(3, Gen.alphaNumStr.map(_.take(4)))
      cl   <- Gen.listOfN(3, Gen.alphaNumStr.map(_.take(4)))
      sn   <- bools
      bins <- Gen.listOfN(3, Gen.zip(Gen.choose(0, 999), Gen.choose(0, 999)))
    } yield {
      def binList = bins.map { case (a, b) => "(" + (a / 8.0) + ", " + (b / 8.0) + ")" }.mkString("[", ", ", "]")
      WidgetSrc(r.decls,
        "(styleBox (StyleBoxProps \"" + xt.take(5) + "\" \"" + yt.take(5) + "\" \"sbAmount\" \"" +
          at.take(5) + "\" " + af._1 + " \"sbX\" \"sbY\" [" +
          rl.map("\"" + _ + "\"").mkString(", ") + "] [" + cl.map("\"" + _ + "\"").mkString(", ") +
          "] " + sn + " " + binList + " " + binList + " (Inline " + r.expr + ")))",
        "styleBox", "Layout.Widgets.StyleBox", "StyleBoxProps",
        "wrap-Inline" :: ("shownumber-" + sn) :: af._2)
    }

  val widgetSrc: Gen[WidgetSrc] =
    Gen.frequency((3, tableSrc), (2, drilldownSrc), (2, scorecardSrc), (2, headlineSrc),
                  (2, crosstabSrc),
                  (3, axisChartSrc), (2, pieSrc), (2, drilldownPieSrc),
                  (2, styleBoxSrc), (2, drilldownBarSrc))

  /** A whole document: a layout tree over generated widgets. */
  final case class DocSrc(decls: List[String], expr: String, widgets: List[WidgetSrc])

  def docSrc(depth: Int): Gen[DocSrc] = {
    val leaf = widgetSrc.map(w => DocSrc(w.decls, w.expr, List(w)))
    if (depth <= 0) leaf
    else {
      def kids(max: Int) = Gen.choose(1, max).flatMap(m => Gen.listOfN(m, docSrc(depth - 1)))
      def join(ss: List[DocSrc]) = (ss.flatMap(_.decls), ss.flatMap(_.widgets))
      Gen.frequency(
        (3, leaf),
        (1, kids(3).map { ss => val (d, w) = join(ss); DocSrc(d, "(vflow " + ss.map(_.expr).mkString("[", ", ", "]") + ")", w) }),
        (1, kids(3).map { ss => val (d, w) = join(ss); DocSrc(d, "(hflow " + ss.map(_.expr).mkString("[", ", ", "]") + ")", w) }),
        (1, Gen.choose(1, 2).flatMap(m => Gen.listOfN(m, kids(2))).map { rows =>
           val (d, w) = join(rows.flatten)
           DocSrc(d, "(grid " + rows.map(_.map(_.expr).mkString("[", ", ", "]")).mkString("[", ", ", "]") + ")", w) }),
        (1, kids(2).flatMap(ss => Gen.listOfN(ss.length, Gen.alphaNumStr.map(_.take(5))).map(ls => (ss, ls))).map {
           case (ss, ls) =>
             val (d, w) = join(ss)
             DocSrc(d, "(tabbed " + ls.zip(ss).map { case (l, s) => "(\"" + l + "\", " + s.expr + ")" }.mkString("[", ", ", "]") + ")", w) }))
    }
  }

  // =====================================================================
  // writing a generated document

  def cache(): MemoryPlanCache =
    new MemoryPlanCache(3600000L, 4096, () => System.currentTimeMillis, new java.security.SecureRandom)

  final case class Written(text: String, json: Json, tokens: Map[String, String])

  private final case class Complaint(why: String) extends RuntimeException(why) with scala.util.control.NoStackTrace
  private def complain(why: String): Nothing = throw Complaint(why)

  /** Evaluate the generated source, write the document, and resolve every
    * deferred token to the inline object the runner would answer with -- the
    * client corpus needs both halves to exercise `resolveRelation`. */
  def write(src: DocSrc, cfg: WriteConfig): Written = {
    val decls = (src.decls.distinct ++ List("gv : Node", "gv = " + src.expr)).mkString("\n")
    val rt = try fixture.defAndEval(decls, "gv", imps)
             catch { case e: Throwable => complain("load/eval threw " + e + "\n" + decls) }
    val doc = Doc.fromRuntime(rt).fold(e => complain("Doc.fromRuntime refused: " + e.report + "\n" + decls), identity)
    val c = cache()
    val sb = new java.lang.StringBuilder
    Write.doc[Id](Doc.document(doc), sb, cfg, c)(new TestDoc.ListScanner, Guard.id)
    val text = sb.toString
    val json = Parse.parse(text).fold(e => complain("unparseable: " + e + "\n" + text.take(400)), identity)
    val tokens = collectTokens(json).map { t =>
      val body = new java.lang.StringBuilder
      Write.relation[Id](t, body, c)(new TestDoc.ListScanner, Guard.id) match {
        case Some(_) => (t, body.toString)
        case None    => complain("token " + t + " did not resolve")
      }
    }.toMap
    Written(text, json, tokens)
  }

  private def collectTokens(j: Json): List[String] = {
    val out = new ListBuffer[String]
    def go(x: Json): Unit =
      if (x.isArray) x.arrayOrEmpty.foreach(go)
      else if (x.isObject) {
        if (x.field(Wire.Kind).flatMap(_.string) == Some(Wire.Deferred))
          x.field(Wire.Token).flatMap(_.string).foreach(out += _)
        x.objectValues.foreach(_.foreach(go))
      }
    go(j)
    out.toList.distinct
  }

  // =====================================================================
  // the exported schemas, once per run

  private lazy val schemas: Map[String, Json] = session { implicit env =>
    Session.loadModules(imps.keySet.toList.filter(_ != "Test"))
    List(("table", "Layout.Widgets.Table", "TableProps"),
         ("drilldownTable", "Layout.Widgets.Drilldown", "DrilldownTableProps"),
         ("scorecard", "Layout.Widgets.Scorecard", "ScorecardProps"),
         ("headline", "Layout.Widgets.Headline", "HeadlineProps"),
         ("crosstab", "Layout.Widgets.Crosstab", "CrosstabProps"),
         ("axisChart", "Layout.Widgets.AxisChart", "AxisChartProps"),
         // both pie registry names come off the ONE props type
         ("pieChart", "Layout.Widgets.PieChart", "PieChartProps"),
         ("drilldownPieChart", "Layout.Widgets.PieChart", "PieChartProps"),
         ("styleBox", "Layout.Widgets.StyleBox", "StyleBoxProps"),
         ("drilldownBar", "Layout.Widgets.DrilldownBar", "DrilldownBarProps"),
         ("$node", "Layout.Doc", "Node")).map { case (k, m, n) =>
      (k, Schema.exportNamed(m, n).fold(e => sys.error("exportNamed " + m + "." + n + ": " + e.report), identity))
    }.toMap
  }

  /** Every `{"tag":"Widget",...}` node of a document, in walk order. */
  def widgetNodes(root: Json): List[(String, Json)] = {
    val out = new ListBuffer[(String, Json)]
    def go(x: Json): Unit =
      if (x.isArray) x.arrayOrEmpty.foreach(go)
      else if (x.isObject) {
        if (x.field("tag").flatMap(_.string) == Some("Widget"))
          for { n <- x.field("name").flatMap(_.string); p <- x.field("props") } out += ((n, p))
        x.objectValues.foreach(_.foreach(go))
      }
    go(root)
    out.toList
  }

  /** One structural mutation of a props document, for the anti-vacuity check:
    * drop a key, retype a leaf, or add one.  `None` when the props hold nothing
    * a mutation could reach. */
  /** The prop fields declared `Maybe a`, whose key is optional on the wire. */
  val optionalKeys: Set[String] =
    Set("rowGroup", "cardDelta",
        // J3e's Maybe fields
        "lowerBound", "upperBound", "colorColumn",
        "pieColorColumn", "pieChildColumn", "pieParentColumn")

  def mutate(j: Json, seed: Long): Option[Json] = {
    val sites = new ListBuffer[List[String]]
    def walk(x: Json, path: List[String]): Unit =
      if (x.isObject) {
        x.objectFieldsOrEmpty.foreach { k => sites += (path :+ k); x.field(k).foreach(walk(_, path :+ k)) }
      }
    walk(j, Nil)
    if (sites.isEmpty) None else {
      val rnd = new scala.util.Random(seed)
      val path = sites(rnd.nextInt(sites.length))
      // a field whose Ermine type is `Maybe a` is an OPTIONAL key (the encoder
      // omits it for Nothing), so DROPPING one is not a mutation the schema can
      // refuse -- retype or add instead
      val how = if (optionalKeys(path.last)) 1 + rnd.nextInt(2) else rnd.nextInt(3)
      def at(x: Json, p: List[String]): Json = p match {
        case Nil => x
        case k :: rest if rest.isEmpty =>
          val cur = x.field(k)
          how match {
            case 0 => Json.jObjectAssocList(x.objectFieldsOrEmpty.filterNot(_ == k).map(f => (f, x.field(f).get)))
            case 1 => x.withObject(o => o + (k, cur match {
                        case Some(v) if v.isString => Json.jNumber(1)
                        case _                     => Json.jString("mutant")
                      }))
            case _ => x.withObject(o => o + (k + "X", Json.jString("extra")))
          }
        case k :: rest => x.withObject(o => o + (k, at(x.field(k).get, rest)))
      }
      Some(at(j, path))
    }
  }

  // =====================================================================
  // (a) the document half of the contract

  private val caseA: Gen[(DocSrc, WriteConfig)] =
    for {
      s    <- docSrc(2)
      dflt <- Gen.oneOf(Delivery.Inline: Delivery, Delivery.Deferred: Delivery)
      thr  <- Gen.frequency((3, Gen.const(None: Option[Long])), (1, Gen.choose(0L, 4L).map(Some(_))))
    } yield (s, WriteConfig(default = dflt, threshold = thr))

  /** Returns the tags seen, or a complaint. */
  def checkA(src: DocSrc, cfg: WriteConfig, seed: Long): Either[String, List[String]] = try {
    val w = write(src, cfg)
    val root = w.json.field(Wire.Root).getOrElse(complain("no root"))
    val nodeErrs = Validate.check(schemas("$node"), root)
    if (nodeErrs.nonEmpty) complain("Layout.Doc.Node: " + nodeErrs.mkString("; "))
    val nodes = widgetNodes(root)
    if (nodes.length != src.widgets.length)
      complain("walked " + nodes.length + " widgets, generated " + src.widgets.length)
    val tags = new ListBuffer[String]
    nodes.zip(src.widgets).foreach { case ((name, props), spec) =>
      if (name != spec.widget) complain("widget name " + name + " != " + spec.widget)
      val schema = schemas(name)
      val errs = Validate.check(schema, props)
      if (errs.nonEmpty) complain(name + " props rejected: " + errs.mkString("; ") + "\n" + props.nospaces.take(600))
      tags += ("widget-" + name)
      List("rows", "ddRows", "cards", "chartRows", "barRows", "pieRows", "styleBoxRows")
        .flatMap(props.field(_)).headOption
        .flatMap(_.field(Wire.Kind)).flatMap(_.string).foreach(k => tags += ("kind-" + k))
      // anti-vacuity: one mutation of these very props must be refused
      mutate(props, seed) match {
        case None => tags += "unmutatable"
        case Some(m) =>
          if (m == props) tags += "mutation-identical"
          else if (Validate.check(schema, m).isEmpty)
            complain(name + " ACCEPTED a mutant: " + m.nospaces.take(600))
          else tags += "mutant-rejected"
      }
      tags ++= spec.tags
    }
    Right(tags.toList)
  } catch { case Complaint(why) => Left(why) }

  property("(a) random prop values written by Write.doc validate against the exported schemas") =
    forAllNoShrink(caseA, Gen.choose(0L, 1000000L)) { (c: (DocSrc, WriteConfig), seed: Long) =>
      checkA(c._1, c._2, seed) match {
        case Right(_) => proved
        case Left(m)  => falsified :| m
      }
    }

  property("(a-cov) over 200 fixed cases every widget, every CellFormat case and both deliveries occur") = secure {
    val results = TestDoc.samples(caseA, 200, 8891L).zipWithIndex.map { case ((s, cfg), i) => checkA(s, cfg, i.toLong) }
    val bad = results.collect { case Left(m) => m }
    val tags = results.collect { case Right(t) => t }.flatten.toSet
    val wantWidgets = Set("widget-table", "widget-drilldownTable", "widget-scorecard",
                          "widget-headline", "widget-crosstab",
                          "widget-axisChart", "widget-pieChart", "widget-drilldownPieChart",
                          "widget-styleBox", "widget-drilldownBar")
    val wantFormats = Set("Default", "Verbatim", "Markdown", "Constant", "Percentage", "Currency",
                          "Pr1", "Pr2", "DateRange", "Round", "IntegralRound", "Truncate",
                          "Conditional", "Color", "Alias")
    val wantKinds = Set("kind-inline", "kind-deferred")
    val wantWraps = Set("wrap-bare", "wrap-Inline")
    // J3e: every chart variant, both axis constraint arms, both pie shapes and
    // both presence/absence of the optional colour column
    val wantChart = Set("variant-Line", "variant-Bar", "variant-Step", "variant-Scatter",
                        "variant-StackedBar", "variant-StackedArea", "variant-BoxAndWhiskers",
                        "variant-Bubble", "axis-scaled", "axis-unscaled",
                        "pie-flat", "pie-drilldown", "color-absent", "color-column",
                        "shownumber-True", "shownumber-False")
    (bad.isEmpty :| (bad.length + " of 200 failed:\n" + bad.take(2).mkString("\n---\n"))) &&
      ((wantWidgets -- tags).isEmpty :| ("widgets never generated: " + (wantWidgets -- tags))) &&
      ((wantFormats -- tags).isEmpty :| ("CellFormat cases never generated: " + (wantFormats -- tags))) &&
      ((wantKinds -- tags).isEmpty :| ("deliveries never seen: " + (wantKinds -- tags))) &&
      ((wantWraps -- tags).isEmpty :| ("relation wrappers never generated: " + (wantWraps -- tags))) &&
      ((wantChart -- tags).isEmpty :| ("chart shapes never generated: " + (wantChart -- tags))) &&
      // J3i: both crosstab shapes -- one with an absent cell and one without --
      // so the `null` arm of `cells` is not merely declared
      ((Set("crosstab-gap", "crosstab-full") -- tags).isEmpty :|
        ("crosstab shapes never generated: " + (Set("crosstab-gap", "crosstab-full") -- tags))) &&
      (tags.contains("mutant-rejected") :| "no mutation was ever refused -- (a) is vacuous")
  }

  // =====================================================================
  // pins

  property("(a-pin) the wire spelling of a scorecard, a CellFormat and a nullary constructor") = secure {
    val decls = List("field wfName : String", "field wfValue : Double",
      "gv : Node",
      "gv = scorecard (ScorecardProps \"T\" \"wfName\" \"wfValue\" Nothing (Round False True 2) " +
        "(Inline (mkRelation# (toList# [{ wfName = \"a\", wfValue = 1.5 }]))))").mkString("\n")
    val rt = fixture.defAndEval(decls, "gv", imps)
    val doc = Doc.fromRuntime(rt).fold(e => sys.error(e.report), identity)
    val sb = new java.lang.StringBuilder
    Write.doc[Id](Doc.document(doc), sb, WriteConfig(), cache())(new TestDoc.ListScanner, Guard.id)
    val want =
      "{\"version\":1,\"settings\":{},\"root\":{\"tag\":\"Widget\",\"name\":\"scorecard\",\"props\":" +
      "{\"title\":\"T\",\"cardLabel\":\"wfName\",\"cardValue\":\"wfValue\"," +
      "\"cardFormat\":{\"tag\":\"Round\",\"color\":false,\"negParens\":true,\"places\":2}," +
      "\"cards\":{\"kind\":\"inline\",\"columns\":[{\"name\":\"wfName\",\"type\":\"String\",\"nullable\":false}," +
      "{\"name\":\"wfValue\",\"type\":\"Double\",\"nullable\":false}],\"rows\":[[\"a\",1.5]],\"rowCount\":1}}}}"
    (sb.toString ?= want) :| ("got " + sb.toString)
  }

  property("(a-pin2) a nullary CellFormat constructor carries an empty args array") = secure {
    val decls = List("field wfName : String",
      "gv : Node",
      "gv = scorecard (ScorecardProps \"T\" \"wfName\" \"wfName\" Nothing Default " +
        "(Inline (mkRelation# (toList# [{ wfName = \"a\" }]))))").mkString("\n")
    val rt = fixture.defAndEval(decls, "gv", imps)
    val doc = Doc.fromRuntime(rt).fold(e => sys.error(e.report), identity)
    val sb = new java.lang.StringBuilder
    Write.doc[Id](Doc.document(doc), sb, WriteConfig(), cache())(new TestDoc.ListScanner, Guard.id)
    (sb.toString.contains("\"cardFormat\":{\"tag\":\"Default\",\"args\":[]}") :| sb.toString)
  }

  property("(a-pin5) the wire spelling of a crosstab: a Nothing INSIDE a list is a null ELEMENT") = secure {
    val decls = List("gv : Node",
      "gv = crosstab (CrosstabProps \"T\" \"Region\" \"Month\" [\"north\", \"south\"] [\"jan\", \"feb\"] " +
        "[[Just 1.5, Nothing], [Nothing, Just 2.0]] [1.5, 2.0] [1.5, 2.0] 3.5 Default)").mkString("\n")
    val rt = fixture.defAndEval(decls, "gv", imps)
    val doc = Doc.fromRuntime(rt).fold(e => sys.error(e.report), identity)
    val sb = new java.lang.StringBuilder
    Write.doc[Id](Doc.document(doc), sb, WriteConfig(), cache())(new TestDoc.ListScanner, Guard.id)
    // the pair no row had is `null` where the number would be -- NOT an absent
    // key (that is what a named `Maybe` FIELD does, e.g. ScorecardProps.cardDelta
    // in (a-pin)), and not a hole in the array
    val want =
      "{\"version\":1,\"settings\":{},\"root\":{\"tag\":\"Widget\",\"name\":\"crosstab\",\"props\":" +
      "{\"crosstabTitle\":\"T\",\"rowHeader\":\"Region\",\"colHeader\":\"Month\"," +
      "\"crosstabRowLabels\":[\"north\",\"south\"],\"crosstabColLabels\":[\"jan\",\"feb\"]," +
      "\"cells\":[[1.5,null],[null,2.0]]," +
      "\"rowTotals\":[1.5,2.0],\"colTotals\":[1.5,2.0],\"grandTotal\":3.5," +
      "\"crosstabFormat\":{\"tag\":\"Default\",\"args\":[]}}}}"
    (sb.toString ?= want) :| ("got " + sb.toString)
  }

  property("(a-pin4) the wire spelling of an axis chart: nullary variant, absent bounds") = secure {
    val decls = List("field wfName : String", "field wfValue : Double",
      "gv : Node",
      "gv = axisChart (AxisChartProps " +
        "(ChartMeta \"T\" (ChartAxis \"x\" \"x\" Default (Scalar \"String\" False) True (Unscaled [Asc] [])) " +
        "(ChartAxis \"y\" \"y\" (Round False False 1) (Scalar \"Double\" True) True (Scaled Nothing (Just 9.0) Linear)) " +
        "Vertical (ChartLegendOptions LegendAbove) (ChartRenderHints False)) " +
        "[(ChartSeries [] [\"wfName\"] \"wfValue\" [] Nothing (Constant \"S\") [] Line)] " +
        "(mkRelation# (toList# [{ wfName = \"a\", wfValue = 1.5 }])))").mkString("\n")
    val rt = fixture.defAndEval(decls, "gv", imps)
    val doc = Doc.fromRuntime(rt).fold(e => sys.error(e.report), identity)
    val sb = new java.lang.StringBuilder
    Write.doc[Id](Doc.document(doc), sb, WriteConfig(), cache())(new TestDoc.ListScanner, Guard.id)
    val s = sb.toString
    // a nullary constructor of a multi-constructor type is {"tag":..,"args":[]},
    // a Maybe field that is Nothing has NO key at all, and Just carries the value
    (s.contains("\"variant\":{\"tag\":\"Line\",\"args\":[]}") :| ("variant: " + s)) &&
      (s.contains("\"constraints\":{\"tag\":\"Scaled\",\"upperBound\":9.0,\"displayScale\":\"Linear\"}")
         :| ("range constraints: " + s)) &&
      (s.contains("\"constraints\":{\"tag\":\"Unscaled\",\"sortOrders\":[\"Asc\"],\"tickOverrides\":[]}")
         :| ("domain constraints: " + s)) &&
      (!s.contains("lowerBound") :| ("a Nothing bound left a key behind: " + s)) &&
      (!s.contains("colorColumn") :| ("a Nothing colorColumn left a key behind: " + s))
  }

  property("(a-pin3) each prop type exports one schema with its row parameter free") = secure {
    val ids = List(("Layout.Widgets.Table", "TableProps"),
                   ("Layout.Widgets.Drilldown", "DrilldownTableProps"),
                   ("Layout.Widgets.Scorecard", "ScorecardProps"),
                   ("Layout.Widgets.AxisChart", "AxisChartProps"),
                   ("Layout.Widgets.PieChart", "PieChartProps"),
                   ("Layout.Widgets.StyleBox", "StyleBoxProps"),
                   ("Layout.Widgets.DrilldownBar", "DrilldownBarProps")).map { case (m, n) =>
      session { implicit env =>
        Session.loadModules(List(m))
        Schema.exportNamed(m, n).fold(e => "ERR " + e.report,
          j => j.field("$id").flatMap(_.string).getOrElse("?"))
      }
    }
    ids ?= List("ermine:Layout.Widgets.Table/TableProps r",
                "ermine:Layout.Widgets.Drilldown/DrilldownTableProps r",
                "ermine:Layout.Widgets.Scorecard/ScorecardProps r",
                "ermine:Layout.Widgets.AxisChart/AxisChartProps r",
                "ermine:Layout.Widgets.PieChart/PieChartProps r",
                "ermine:Layout.Widgets.StyleBox/StyleBoxProps r",
                "ermine:Layout.Widgets.DrilldownBar/DrilldownBarProps r")
  }
}

/** Writes the cross-language corpus property (b) runs on:
  *
  *   sbt -batch 'core/Test/runMain com.clarifi.reporting.WidgetCorpus <dir> [n] [seed]'
  *   client/scripts/check-corpus.sh <dir>
  *
  * `<dir>/NNN.json` is a document, `<dir>/NNN.tokens.json` the `{token: inline
  * relation}` map the client's fetch stub answers deferred relations from (the
  * runner's `GET /data/<token>` in a file), and `<dir>/manifest.json` lists them.
  */
object WidgetCorpus {
  def main(args: Array[String]): Unit = {
    com.clarifi.reporting.util.Logging.initializeLogging
    val dir = new java.io.File(if (args.length > 0) args(0) else "target/widget-corpus")
    val n = if (args.length > 1) args(1).toInt else 200
    val seed = if (args.length > 2) args(2).toLong else 5150L
    dir.mkdirs()
    val cases = TestDoc.samples(
      for {
        s    <- TestWidgets.docSrc(2)
        dflt <- Gen.oneOf(Delivery.Inline: Delivery, Delivery.Deferred: Delivery)
        thr  <- Gen.frequency((3, Gen.const(None: Option[Long])), (1, Gen.choose(0L, 4L).map(Some(_))))
      } yield (s, WriteConfig(default = dflt, threshold = thr)), n, seed)
    val names = new ListBuffer[String]
    cases.zipWithIndex.foreach { case ((s, cfg), i) =>
      val stem = "%03d".format(i)
      val w = TestWidgets.write(s, cfg)
      writeText(new java.io.File(dir, stem + ".json"), w.text)
      writeText(new java.io.File(dir, stem + ".tokens.json"),
                w.tokens.toList.sortBy(_._1).map { case (t, body) =>
                  "  " + Json.jString(t).nospaces + ": " + body }.mkString("{\n", ",\n", "\n}\n"))
      names += stem
    }
    writeText(new java.io.File(dir, "manifest.json"),
              names.map(s => "  \"" + s + "\"").mkString("[\n", ",\n", "\n]\n"))
    println("wrote " + names.length + " documents to " + dir.getAbsolutePath)
  }

  private def writeText(f: java.io.File, s: String): Unit = {
    val out = new java.io.OutputStreamWriter(new java.io.FileOutputStream(f), "UTF-8")
    try out.write(s) finally out.close()
  }
}

/** The end-to-end fixture: evaluates `Doc.SalesReport.report`
  * (core/src/test/resources/modules/Doc/SalesReport.e) and writes the JSON
  * document on a SQLite in-memory connection -- the whole pipeline J3c will put
  * an HTTP server in front of.
  *
  *   sbt -batch 'core/Test/runMain com.clarifi.reporting.SalesReportDoc <file>'
  *
  * client/test/endtoend.test.ts renders exactly that file.
  */
object SalesReportDoc {
  import com.clarifi.reporting.backends.{ DB, Scanners, Runners }
  import com.clarifi.reporting.relational.SMEnv

  /** The document text, written through Write.doc on one SQLite connection. */
  def write(): String = {
    val fixture = ErmineFixture()
    import fixture.{ all, ImportSpec }
    val imps: Map[String, ImportSpec] = Map("Builtin" -> all, "Doc.SalesReport" -> all)
    val rt = fixture.defAndEval("", "report", imps)
    val doc = Doc.fromRuntime(rt).fold(e => sys.error("Doc.fromRuntime: " + e.report), identity)
    val S = Scanners.SQLite(SMEnv.dummySmenv)
    val R = Runners.SQLite("jdbc:sqlite::memory:")
    val sb = new java.lang.StringBuilder
    R.run(Write.doc[DB](Doc.document(doc), sb, WriteConfig(), TestWidgets.cache())(S, Guard.db))
    sb.toString
  }

  def main(args: Array[String]): Unit = {
    com.clarifi.reporting.util.Logging.initializeLogging
    val text = write()
    val target = if (args.length > 0) args(0) else "target/sales-report.json"
    val f = new java.io.File(target)
    Option(f.getParentFile).foreach(_.mkdirs())
    val out = new java.io.OutputStreamWriter(new java.io.FileOutputStream(f), "UTF-8")
    try out.write(text) finally out.close()
    println("wrote " + f.getAbsolutePath + " (" + text.length + " chars)")
  }
}
