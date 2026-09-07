package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.relational.{ExtMem, Pivot}

import org.scalacheck.{ Prop, Properties }
import Prop.{ Result => _, _ }

/** Stage F1, ticket A1: the record primitives, FORCED.
  *
  * `Native.Record.record#` answers the Ermine `Record#` -- a `Map[String,Runtime]`.  Scala
  * 2.13 made `Map#mapValues` return a lazy `MapView`, which is NOT a `Map`, so the primitive
  * published a `MapView` and every consumer that pattern-matches `Prim(_: Map[...])`
  * (`scalaRecord#`, `scalaRecordIn#`, `header#`) fell through `whnfMatch` to its panic:
  *
  *   Panic: unexpected runtime value in Native.Record.scalaRecord# - MapView(<not computed>)
  *
  * `core/examples/PivotTest.e`'s `pivotData` had been in the tree for years and could not be
  * evaluated; `Relation.Predicate.all`, `Record.header`, `Record.anyRecordOrd`,
  * `Relation.Sort.partialRecordOrd`, `Relation.nonEmptyRelation`, `Layout.Chart.srecKeys` and
  * `Layout.Presentation` were all in the same position.  NOTHING CAUGHT IT BECAUSE NOTHING
  * FORCED A PIVOT: Ermine is lazy and `:load` type-checks without evaluating.
  *
  * Every property here therefore evaluates to a VALUE and looks at it.  Two shapes of check,
  * deliberately:
  *
  *   * structural -- the Scala object behind the runtime value is a `Map`, the pivot node
  *     carries one real key `Record` per pivoted column.  A `MapView` fails these directly,
  *     which is the defect rather than its symptom.
  *   * rendered -- the value's own `toString` (`Pretty.ppRuntime`, what the REPL prints) must
  *     contain no `<error:` and no `MapView`.  This is exactly what a user saw, and it also
  *     catches a `MapView` that travels somewhere new rather than panicking here.
  */
object TestRecordPrims extends Properties("record primitives forced (A1)") {
  private val fx = ErmineFixture()
  import fx.defAndEval

  /** Imports go in the STATEMENT text, not in this map: `loadStatements` renders an import
    * map as plain `import M` lines and the pivot module needs `hiding` / `using` (as
    * `core/examples/PivotTest.e` does, to keep `Relation.Row`'s brace syntax). */
  private val onlyTest = Map("Test" -> fx.all)

  private def shown(r: Runtime): String = r.toString

  private def clean(what: String, r: Runtime): Prop = {
    val s = shown(r)
    ((!s.contains("<error:")) :| (what + " rendered an error: " + s)) &&
    ((!s.contains("MapView")) :| (what + " rendered a MapView: " + s))
  }

  // ---------------------------------------------------------------- the primitives

  private val recordProbes =
    """import Native.Record
      |
      |field aa, bb : Int
      |
      |recProbe  = record# { aa = 1, bb = 2 }
      |srecProbe = scalaRecord# recProbe
      |backProbe = scalaRecordIn# srecProbe
      |hdrProbe  = header# recProbe
      |""".stripMargin

  property("record# answers a strict Map, not a 2.13 MapView") = secure {
    val r = defAndEval(recordProbes, "recProbe", onlyTest).whnf
    val p = r.extract[Any]
    ((p.isInstanceOf[scala.collection.immutable.Map[_, _]]) :|
       ("record# answered " + p.getClass.getName + ": " + p)) &&
    (p.asInstanceOf[Map[String, Runtime]].keySet ?= Set("aa", "bb"))
  }

  property("scalaRecord# forces to a Record") = secure {
    val r = defAndEval(recordProbes, "srecProbe", onlyTest).whnf
    val p = r.extract[Any]
    ((p.isInstanceOf[scala.collection.immutable.Map[_, _]]) :|
       ("scalaRecord# answered " + p.getClass.getName + ": " + p)) &&
    (p.asInstanceOf[Record] ?= Map("aa" -> IntExpr(false, 1),
                                   "bb" -> IntExpr(false, 2))) &&
    clean("scalaRecord#", r)
  }

  property("scalaRecordIn# forces back to a Record#") = secure {
    val r = defAndEval(recordProbes, "backProbe", onlyTest).whnf
    val p = r.extract[Any]
    ((p.isInstanceOf[scala.collection.immutable.Map[_, _]]) :|
       ("scalaRecordIn# answered " + p.getClass.getName + ": " + p)) &&
    (p.asInstanceOf[Map[String, Runtime]].keySet ?= Set("aa", "bb")) &&
    clean("scalaRecordIn#", r)
  }

  property("Native.Record.header# reads a forced record's header") = secure {
    val r = defAndEval(recordProbes, "hdrProbe", onlyTest).whnf
    (r.extract[List[(String, PrimT)]].toSet ?=
       Set("aa" -> PrimT.IntT(false), "bb" -> PrimT.IntT(false))) &&
    clean("header#", r)
  }

  // ---------------------------------------------------------------- the stdlib consumers

  /** `Record.header` is `Row . map fromPair# . fromList# . header# . record#`.  It is imported
    * WITHOUT `Prelude`, which re-exports `Record` under an affix and leaves the bare name
    * unbound. */
  property("Record.header forces to a Row over the record's fields") = secure {
    val r = defAndEval(
      """import Record
        |
        |field cc, dd : Int
        |
        |hdrRow = header { cc = 1, dd = 2 }
        |""".stripMargin, "hdrRow", onlyTest)
    clean("Record.header", r) &&
    (shown(r).contains("cc") :| ("Record.header lost cc: " + shown(r))) &&
    (shown(r).contains("dd") :| ("Record.header lost dd: " + shown(r)))
  }

  /** `Relation.Predicate.all` is `fromRecord# predicateModule . scalaRecord# . record#`; the
    * value is the Scala `Predicate` the relational layer filters with. */
  property("Relation.Predicate.all builds a real Predicate") = secure {
    val r = defAndEval(
      """import Prelude
        |import Relation.Predicate
        |
        |field ee, ff : Int
        |
        |allProbe = all { ee = 1, ff = 2 }
        |""".stripMargin, "allProbe", onlyTest).whnf
    val p = r.extract[Predicate]
    (p.columnReferences ?= Set("ee", "ff")) && clean("Predicate.all", r)
  }

  // ---------------------------------------------------------------- THE PIVOT, FORCED

  /** `core/examples/PivotTest.e` inline, cut to two pivoted columns.  This is the module the
    * reports named: before the fix, forcing it answered the panic and nothing else. */
  private val pivotModule =
    """import Prelude
      |import Relation.Pivot hiding single_Brace; snoc_Brace
      |import Relation.Op using col
      |
      |field Issue : String
      |field Key, Value : String
      |field Sector, Price : String
      |
      |myData : Mem (| Issue, Key, Value |)
      |myData = mem
      |  [ { Issue = "MSFT", Key = "Sector", Value = "Technology" }
      |  , { Issue = "MSFT", Key = "Price",  Value = "33.72" }
      |  , { Issue = "GOOG", Key = "Sector", Value = "Technology" }
      |  , { Issue = "GOOG", Key = "Price",  Value = "1025" }
      |  ]
      |
      |f0 = nilFulcrum {Key} {Value}
      |f1 = consFulcrum Sector (col Value) { Key = "Sector" } f0
      |f2 = consFulcrum Price  (col Value) { Key = "Price" }  f1
      |
      |pivotData = pivot f2 myData
      |""".stripMargin

  property("a forced pivot carries one real key row per pivoted column") = secure {
    val r = defAndEval(pivotModule, "pivotData", onlyTest).whnf
    r match {
      case Rel(ExtMem(Pivot(_, pk, pv, _, colMap))) =>
        // the plan the pivot compiles to: keys, values and one entry per new column
        ((pk ?= Set("Key")) :| "pivot key") &&
        ((pv ?= Set("Value")) :| "pivot values") &&
        ((colMap.keySet ?= Set("Sector", "Price")) :| "pivoted columns") &&
        // each entry's ROW is the `record# k` that used to be a MapView
        Prop.all(colMap.toList.map { case (col, (row, _, _)) =>
          ((row.isInstanceOf[scala.collection.immutable.Map[_, _]]) :|
             (col + "'s key row is a " + row.getClass.getName)) &&
          ((row: Map[String, PrimExpr]) ?= Map("Key" -> StringExpr(false, col)))
        }: _*)
      case other =>
        falsified :| ("forcing the pivot did not answer a relation: " + other.toString)
    }
  }

  property("a forced pivot renders with no panic and no MapView") = secure {
    clean("pivotData", defAndEval(pivotModule, "pivotData", onlyTest))
  }
}
