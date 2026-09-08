package com.clarifi.reporting
package relational

import com.clarifi.machines.{Process, Source}
import com.clarifi.reporting.backends.{Scanners, DB}
import com.clarifi.reporting.SortOrder._
import com.clarifi.reporting.PrimT._

import scalaz.Id.Id
import scalaz.std.list._

import org.scalacheck.{ Prop, Properties }
import Prop.{ Result => _, _ }

/** Stage F3, ticket A1b: the three IN-MEMORY record paths the 2.13 migration left
  * comparing or hashing a `MapView`.
  *
  * The 2.13 collections made `Map#filterKeys` return a lazy `MapView`, which is not a
  * `Map` and does not have `Map`'s `equals`/`hashCode` -- it inherits `Object`'s, so
  * two views over equal maps are never equal and never hash alike.  Where the
  * migration's result was passed somewhere that WANTED a `Map` the compiler rejected it
  * (~20 such sites were fixed then); where it was only COMPARED or HASHED nothing was
  * rejected and the code silently stopped working:
  *
  *   - `SqlScanner.pivot`'s `prime` (`:644` before the fix) tested `kr == k` against a
  *     view, so the FIRST row of every pivot group contributed nothing and each pivoted
  *     column got its DEFAULT;
  *   - `SqlScanner.hashJoin` (`:708`) built the tee's key with a view, so no left key
  *     ever matched a right key and the join emitted NOTHING;
  *   - `relational.sorting`'s chunk predicate (`package.scala:67`) was always false, so
  *     every chunk was one record long, `sort` sorted singletons and the process handed
  *     the INPUT ORDER back.
  *
  * None of the three is reachable from an Ermine program: `Scanners.e` publishes only
  * `dumpClosed`, so the REPL can dump a relation's SQL but never execute a `Mem`, and
  * `Scanner.dumpMem` is unimplemented on `SqlScanner`.  These properties drive the three
  * functions directly, which is why two of them are `private[relational]` now.
  *
  * Every property below FAILS on the pre-fix compiler; the expected wrong answer is
  * named in each.
  */
object TestInMemoryScan extends Properties("in-memory scan paths (A1b)") {

  private def i(n: Int): PrimExpr = IntExpr(false, n)
  private def s(x: String): PrimExpr = StringExpr(false, x)

  private val scanner = Scanners.SQLite(SMEnv.dummySmenv)

  // ------------------------------------------------------------------ the pivot

  /** `metric`/`amount` pivoted into one column per metric, keyed by `id`. */
  private val pKey  = Set("metric")
  private val pVals = Set("amount")
  private val amount: Op = Op.ColumnValue("amount", IntT(false))
  // `a -> (b, c, d)` would parse as a three-argument `->`, so the pairs are written out.
  private val colMap: Map[ColumnName, (Record, Op, PrimExpr)] = Map(
    ("xs", (Map("metric" -> s("x")), amount, i(-1))),
    ("ys", (Map("metric" -> s("y")), amount, i(-1))))

  private val pivotIn: List[Record] = List(
    Map("id" -> s("a"), "metric" -> s("x"), "amount" -> i(1)),
    Map("id" -> s("a"), "metric" -> s("y"), "amount" -> i(2)),
    Map("id" -> s("b"), "metric" -> s("x"), "amount" -> i(3)),
    Map("id" -> s("b"), "metric" -> s("y"), "amount" -> i(4)))

  property("the in-memory pivot keeps the FIRST row of each group") = secure {
    val out = Process.transduce(pivotIn)(scanner.pivot(pKey, pVals, colMap, false)).toList
    // Pre-fix: List(Map(id -> a, xs -> -1, ys -> 2), Map(id -> b, xs -> -1, ys -> 4)) --
    // `prime` compared a MapView to the colMap's key record, so the row that OPENED each
    // group matched no column and every column started at its default.
    out ?= List(Map("id" -> s("a"), "xs" -> i(1), "ys" -> i(2)),
                Map("id" -> s("b"), "xs" -> i(3), "ys" -> i(4)))
  }

  property("a pivot column with no matching row still gets its default") = secure {
    val in = List(Map("id" -> s("c"), "metric" -> s("x"), "amount" -> i(7)))
    val out = Process.transduce(in)(scanner.pivot(pKey, pVals, colMap, false)).toList
    out ?= List(Map("id" -> s("c"), "xs" -> i(7), "ys" -> i(-1)))
  }

  // ------------------------------------------------------------------ the hash join

  private def proc(rs: List[Record]): DB[com.clarifi.machines.Procedure[Id, Record]] =
    (_: java.sql.Connection) => procedureFromSource(Source.source(rs))

  property("the in-memory hash join matches on the key columns") = secure {
    val left = List(Map("k" -> s("a"), "l" -> i(1)),
                    Map("k" -> s("b"), "l" -> i(2)))
    val right = List(Map("k" -> s("b"), "r" -> i(20)),
                     Map("k" -> s("a"), "r" -> i(10)),
                     Map("k" -> s("c"), "r" -> i(30)))
    val joined = scanner.hashJoin(proc(left), proc(right), Set("k"))(null: java.sql.Connection)
    val out = joined.foldLeftM(Vector[Record]())((v, r) => v :+ r).toSet
    // Pre-fix: the empty set -- the two key functions answered MapViews, which hash by
    // identity, so `Tee.hashJoin` never found a match and the join emitted nothing.
    out ?= Set(Map("k" -> s("a"), "l" -> i(1), "r" -> i(10)),
               Map("k" -> s("b"), "l" -> i(2), "r" -> i(20)))
  }

  // ------------------------------------------------------------------ the sort

  property("sorting groups by the columns already in order") = secure {
    val in = List(Map("g" -> i(1), "v" -> i(3)),
                  Map("g" -> i(1), "v" -> i(1)),
                  Map("g" -> i(1), "v" -> i(2)),
                  Map("g" -> i(2), "v" -> i(9)),
                  Map("g" -> i(2), "v" -> i(5)))
    val p = sorting(List("g" -> Asc), List("g" -> Asc, "v" -> Asc))
    val out = Process.transduce(in)(p).toList map (r => (r("g"), r("v")))
    // Pre-fix: the input order back, (1,3) (1,1) (1,2) (2,9) (2,5) -- the chunk predicate
    // compared two MapViews, so every chunk held one record and sorting a singleton is a
    // no-op.
    out ?= List((i(1), i(1)), (i(1), i(2)), (i(1), i(3)),
                (i(2), i(5)), (i(2), i(9)))
  }

  property("sorting leaves a stream that is already in the wanted order alone") = secure {
    val in = List(Map("g" -> i(1), "v" -> i(1)),
                  Map("g" -> i(1), "v" -> i(2)),
                  Map("g" -> i(2), "v" -> i(5)))
    val p = sorting(List("g" -> Asc), List("g" -> Asc, "v" -> Asc))
    Process.transduce(in)(p).toList ?= in
  }
}
