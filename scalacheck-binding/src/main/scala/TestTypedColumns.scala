package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.SessionEnv

import org.scalacheck._
import Prop.{ Result => _, _ }

/** WP-37 (tracker/TYPED-COLUMNS.md): the typed table columns of
  * `Layout.Widgets.Table` -- `col`/`numCol`/`dateCol`, the marks, and `simpleTable`'s
  * lowering to the wire `TableProps`.
  *
  *  - ACCEPTANCE: a typed table lowers to the wire record a hand-written
  *    `TableProps` spells (headers default to the field name; sort and row-group
  *    marks become indices in COLUMN order), compared as rendered JSON.
  *  - D6, MEASURED: `col` on a field of every runtime primitive type picks the kind
  *    and alignment the plan says, nullable variants included.
  *  - REFUSAL: a column the relation lacks, a numeric format on a non-numeric field,
  *    a date column on a non-temporal field, and a column the projection dropped are
  *    TYPE errors, and the message is pinned.
  *
  * The relation's rows never enter the comparison: `wireOf` drops them, since a bare
  * relation has no inline JSON encoding (the document writer resolves it) and the rows
  * are exactly the argument `simpleTable` passes through untouched.
  */
object TestTypedColumns extends Properties("typed table columns (WP-37)") {
  private lazy val fixture = ErmineFixture()
  import fixture._

  val tImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Json" -> all, "List" -> all, "Maybe" -> all,
        "Date" -> all, "Nullable" -> all,
        "Layout.Widgets.Format" -> all, "Layout.Widgets.Table" -> all,
        "Layout.Widgets.Column" -> all,
        // `project_RR (single_RR f) rel` is the sketch's `rel # {f}` (Relation.Row's brackets
        // would clash with List's, so the module comes in under an alias)
        "Relation.Row" -> ((Some("RR"), Nil, false): ImportSpec))

  /** The sketch's relation (scratch-widget-preview/typedcols/TypedCols.e), a projection
    * helper, and `wireOf`: every TableProps field but the rows. */
  val prelude: String = List(
    "field region : String",
    "field day    : Date",
    "field amount : Double",
    "field units  : Int",
    "field target : Double",
    "table sales   : [region, day, amount, units]",
    "table targets : [region, target]",
    "wireOf : TableProps r -> (List TableColumn, Maybe Int, List ColumnSort, Bool, Bool)",
    "wireOf (TableProps cs g ss p sc _) = (cs, g, ss, p, sc)"
  ).mkString("\n")

  /** `render (toJson e)`, canonicalised: object keys sorted, no spaces (the encoder's key
    * order is not part of the wire contract; the client reads objects by key). */
  private def json(stmts: String, e: String): String =
    canon(defAndEval(prelude + "\n" + stmts, "render (toJson (" + e + "))", tImps).extract[String])

  private def canon(s: String): String = {
    def go(j: argonaut.Json): String =
      j.arrayOrObject(j.nospaces,
        a => a.map(go).mkString("[", ",", "]"),
        o => o.toList.sortBy(_._1).map { case (k, v) => argonaut.Json.jString(k).nospaces + ":" + go(v) }
               .mkString("{", ",", "}"))
    argonaut.Parse.parse(s).fold(err => sys.error("not JSON (" + err + "): " + s), go)
  }

  /** The typed table and the hand-written wire table render the same JSON. */
  private def sameWire(typed: String, wire: String): Prop = secure {
    val a = json("", "wireOf (" + typed + ")")
    val b = json("", "wireOf (" + wire + ")")
    (a ?= b) :| ("typed: " + typed + "\n  " + a + "\nwire: " + wire + "\n  " + b)
  }

  /** The refusal text of `e` (after the prelude), or `<accepted: ...>`. */
  private def outcome(e: String, stmts: String = ""): String =
    fixture.run { implicit s =>
      loadStatements(prelude + "\n" + stmts, tImps)
      typeOf(e, tImps)
    } match {
      case scalaparsers.Failure(Some(d), _) => d.toString
      case other                            => "<accepted: " + other + ">"
    }

  private def refusedWith(e: String, msg: String): Prop = secure {
    val o = outcome(e)
    (o contains msg) :| ("expected a refusal containing '" + msg + "' for " + e + ", got: " + o)
  }

  // -- ACCEPTANCE ------------------------------------------------------------------------

  property("sketch `good`: [col day, col amount] lowers to the wire table, headers = field names") =
    sameWire("simpleTable [col day, col amount] sales",
             "TableProps [TableColumn \"day\" \"day\" Default AlignLeft DateColumn, " +
             "TableColumn \"amount\" \"amount\" Default AlignRight NumberColumn] Nothing [] True True sales")

  property("sketch `t2`: numCol with a format, withHeader over dateCol, col over a String") =
    sameWire("simpleTable [numCol amount (Currency False False \"$\" 2), withHeader \"Day\" (dateCol day), col region] sales",
             "TableProps [TableColumn \"amount\" \"amount\" (Currency False False \"$\" 2) AlignRight NumberColumn, " +
             "TableColumn \"day\" \"Day\" Default AlignLeft DateColumn, " +
             "TableColumn \"region\" \"region\" Default AlignLeft OtherColumn] Nothing [] True True sales")

  property("marks lower to indices in column order; the first groupRows wins; knobs override") =
    sameWire("simpleTable [col region, sortDesc (col amount), groupRows (withFormat Verbatim (dateCol day)), " +
               "sortAsc (alignLeft (numCol units Default)), groupRows (alignRight (col region))] sales",
             "TableProps [TableColumn \"region\" \"region\" Default AlignLeft OtherColumn, " +
             "TableColumn \"amount\" \"amount\" Default AlignRight NumberColumn, " +
             "TableColumn \"day\" \"day\" Verbatim AlignLeft DateColumn, " +
             "TableColumn \"units\" \"units\" Default AlignLeft NumberColumn, " +
             "TableColumn \"region\" \"region\" Default AlignRight OtherColumn] " +
             "(Just 2) [ColumnSort 1 True, ColumnSort 3 False] True True sales")

  property("the last sort mark on one column wins; no marks means no sorts and no row group") =
    sameWire("simpleTable [sortDesc (sortAsc (col units)), col amount] sales",
             "TableProps [TableColumn \"units\" \"units\" Default AlignRight NumberColumn, " +
             "TableColumn \"amount\" \"amount\" Default AlignRight NumberColumn] Nothing [ColumnSort 0 True] True True sales") &&
    sameWire("simpleTable [col units] sales",
             "TableProps [TableColumn \"units\" \"units\" Default AlignRight NumberColumn] Nothing [] True True sales")

  property("the literal wire JSON of a marked table (pinned)") = secure {
    val got = json("", "wireOf (simpleTable [col region, sortDesc (col amount), groupRows (dateCol day)] sales)")
    val want =
      "[[{\"align\":\"AlignLeft\",\"cellFormat\":{\"args\":[],\"tag\":\"Default\"},\"column\":\"region\",\"header\":\"region\",\"kind\":\"OtherColumn\"}," +
      "{\"align\":\"AlignRight\",\"cellFormat\":{\"args\":[],\"tag\":\"Default\"},\"column\":\"amount\",\"header\":\"amount\",\"kind\":\"NumberColumn\"}," +
      "{\"align\":\"AlignLeft\",\"cellFormat\":{\"args\":[],\"tag\":\"Default\"},\"column\":\"day\",\"header\":\"day\",\"kind\":\"DateColumn\"}]," +
      "2,[{\"descending\":true,\"sortColumn\":1}],true,true]"
    (got ?= want)
  }

  property("columnName and columnWire read the typed column") = secure {
    json("", "(columnName (withHeader \"R\" (col region)), columnWire (withHeader \"R\" (col region)))") ?=
      json("", "(\"region\", TableColumn \"region\" \"R\" Default AlignLeft OtherColumn)")
  }

  // -- D6, MEASURED per runtime PrimT ------------------------------------------------------

  /** (Ermine value type, PrimT name, expected kind, expected align). */
  val primCases: List[(String, String, String, String)] = List(
    ("Byte",            "Byte",      "NumberColumn", "AlignRight"),
    ("Short",           "Short",     "NumberColumn", "AlignRight"),
    ("Int",             "Int",       "NumberColumn", "AlignRight"),
    ("Long",            "Long",      "NumberColumn", "AlignRight"),
    ("Double",          "Double",    "NumberColumn", "AlignRight"),
    ("Date",            "Date",      "DateColumn",   "AlignLeft"),
    ("Timestamp",       "Timestamp", "DateColumn",   "AlignLeft"),
    ("String",          "String",    "OtherColumn",  "AlignLeft"),
    ("Bool",            "Bool",      "OtherColumn",  "AlignLeft"),
    ("GUID",            "UUID",      "OtherColumn",  "AlignLeft"),
    ("Nullable Int",    "Int",       "NumberColumn", "AlignRight"),
    ("Nullable Double", "Double",    "NumberColumn", "AlignRight"),
    ("Nullable Date",   "Date",      "DateColumn",   "AlignLeft"),
    ("Nullable String", "String",    "OtherColumn",  "AlignLeft"))

  property("D6: col picks kind and alignment from the field's runtime PrimT (every PrimT, nullable too)") = secure {
    val decls = primCases.zipWithIndex.map { case ((t, _, _, _), i) => "field pf" + i + " : " + t }
    val table = "table prims : [" + primCases.indices.map("pf" + _).mkString(", ") + "]"
    val cols  = primCases.indices.map(i => "col pf" + i).mkString("[", ", ", "]")
    val names = primCases.indices.map(i => "primName pf" + i).mkString("[", ", ", "]")
    val got   = json((decls :+ table).mkString("\n"), "(" + names + ", wireOf (simpleTable " + cols + " prims))")
    val want  =
      primCases.map(c => "\"" + c._2 + "\"").mkString("[[", ",", "],") +
      primCases.zipWithIndex.map { case ((_, _, k, a), i) =>
        "{\"align\":\"" + a + "\",\"cellFormat\":{\"args\":[],\"tag\":\"Default\"},\"column\":\"pf" + i +
          "\",\"header\":\"pf" + i + "\",\"kind\":\"" + k + "\"}" }.mkString("[[", ",", "],null,[],true,true]]")
    (got ?= want)
  }

  // -- REFUSAL ---------------------------------------------------------------------------

  property("refused: a column the relation does not have (row partition)") =
    refusedWith("simpleTable [col target] sales", "Row partitions are unsatisfiable at field 'Test.target'")

  property("refused: a column the projection dropped") =
    refusedWith("simpleTable [col region, col day] (project_RR (single_RR region) sales)", "Row partitions are unsatisfiable")

  property("refused: numCol on a String field") =
    refusedWith("simpleTable [numCol region Default] sales", "No instance for (PrimitiveNum String)")

  property("refused: dateCol on a Double field") =
    refusedWith("simpleTable [dateCol amount] sales", "No instance for (PrimitiveTemporal Double)")

  property("the refusals' twins are accepted (anti-vacuity)") = secure {
    val es = List("simpleTable [col target] targets",
                  "simpleTable [col region] (project_RR (single_RR region) sales)",
                  "simpleTable [numCol amount Default] sales",
                  "simpleTable [dateCol day] sales")
    es.map(e => { val o = outcome(e); o.startsWith("<accepted") :| (e + ": " + o) })
      .reduce(_ && _)
  }

  // -- REMOVAL (D2) ------------------------------------------------------------------------

  property("removed: textColumn, numberColumn and legacySimpleTable are undefined") = secure {
    List("textColumn \"region\" \"Region\"",
         "numberColumn \"amount\" \"Amount\" Default",
         "legacySimpleTable [] sales")
      .map(e => { val o = outcome(e); (o contains "undefined term") :| (e + ": " + o) })
      .reduce(_ && _)
  }

  property("removed: simpleTable no longer takes String-named wire columns") = secure {
    val o = outcome("simpleTable [TableColumn \"region\" \"region\" Default AlignLeft OtherColumn] sales")
    o.startsWith("<accepted").unary_! :| o
  }

  // -- THE REAL FIXTURES THROUGH THE REAL RUNNER (review nit N1) ------------------------------
  //
  // TestRunner renders these reports but pins no column kind or sort index.  Expectations
  // are literal copies from the migration dump, scratch-widget-preview/typedcols/expected/
  // (D8 with the D10 day-kind substitution): per `Widget "table"` in document order,
  // `columns[].kind`, `sorts`, and `rowGroup` (absent in every one of them):
  //   Sales.2.json (orderBy ByAmount): [OtherColumn,DateColumn,NumberColumn,NumberColumn]
  //     sorts [{"sortColumn":2,"descending":true}]; [OtherColumn] []; [OtherColumn,NumberColumn,NumberColumn] []
  //   Sales.3.json (orderBy ByDay): the same kinds, first table's sorts [{"sortColumn":1,"descending":false}]
  //   FetchTabs.1.json (showUnits true): 4 x [DateColumn,NumberColumn,NumberColumn] []

  private lazy val fixtureRunner =
    new com.clarifi.reporting.ermine.json.Runner(
      com.clarifi.reporting.ermine.json.RunnerConfig(roots = List("core/src/test/resources/doc")))

  /** One line per table widget: kinds | sorts | rowGroup. */
  private def tablesOf(module: String, params: String): List[String] = {
    val out = new java.lang.StringBuilder
    val body = "{\"" + com.clarifi.reporting.ermine.json.Request.Params + "\":" + params + "}"
    fixtureRunner.renderText(module, body, out) match {
      case Left(e)  => List("<render failed " + e.status + ": " + e.body.take(400) + ">")
      case Right(_) =>
        val doc = argonaut.Parse.parse(out.toString).fold(e => sys.error(e), identity)
        def walk(j: argonaut.Json): List[argonaut.Json] =
          j.arrayOrObject(Nil, _.flatMap(walk), o => {
            val here = if (o("tag").flatMap(_.string).contains("Widget") && o("name").flatMap(_.string).contains("table"))
                         o("props").toList else Nil
            here ++ o.toList.flatMap { case (_, v) => walk(v) }
          })
        walk(doc).map { p =>
          val kinds = p.field("columns").map(_.arrayOrEmpty).getOrElse(Nil).flatMap(_.field("kind")).flatMap(_.string)
          kinds.mkString("[", ",", "]") + " | " + p.field("sorts").map(j => canon(j.nospaces)).getOrElse("<none>") +
            " | " + p.field("rowGroup").map(_.nospaces).getOrElse("absent")
        }
    }
  }

  property("real fixtures: Sales (two sort orders) and FetchTabs pin column kinds, sorts and rowGroup (expected/)") = secure {
    val salesRest = List("[OtherColumn] | [] | absent", "[OtherColumn,NumberColumn,NumberColumn] | [] | absent")
    val main = "[OtherColumn,DateColumn,NumberColumn,NumberColumn]"
    val cases = List(
      ("Sales", "{\"fromDay\": \"2026-01-01\", \"toDay\": \"2026-03-31\", \"orderBy\": \"ByAmount\"}",
        (main + " | [{\"descending\":true,\"sortColumn\":2}] | absent") :: salesRest),
      ("Sales", "{\"fromDay\": \"2026-01-01\", \"toDay\": \"2026-03-31\", \"orderBy\": \"ByDay\"}",
        (main + " | [{\"descending\":false,\"sortColumn\":1}] | absent") :: salesRest),
      ("FetchTabs", "{\"showUnits\": true}",
        List.fill(4)("[DateColumn,NumberColumn,NumberColumn] | [] | absent")))
    cases.map { case (m, ps, want) =>
      val got = tablesOf(m, ps)
      (got ?= want) :| (m + " " + ps)
    }.reduce(_ && _)
  }
}
