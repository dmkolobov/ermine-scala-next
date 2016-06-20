package com.clarifi.reporting
package sql

import scalaz._
import Scalaz._
import org.scalacheck._

import backends._
import Op._
import Predicate._
import PrimT.IntT
import com.clarifi.reporting.relational.SMEnv._
import com.clarifi.reporting.relational._


object SqlEmitterGens {
  import Gen.{value=>_, _}

  /** Like `Gen.listOfN` but guarantee unique elements.  Will not
    * terminate if `elts` won't produce `n` unique elements!
    */
  def setOfN[A](count: Int, elt: Gen[A]): Gen[Set[A]] = {
    def basis(xs: Set[A]): Gen[Set[A]] =
      if (xs.size == count) Gen.const(xs)
      else Gen.listOfN(count - xs.size, elt).flatMap {more => basis(xs ++ more)}
    basis(Set.empty[A])
  }

  private val nonEmptyAlphaStr = alphaStr filter (!_.isEmpty)

  /** Answer the standard Gen instance for Ts. */
  def stdGen[T](implicit ev: Arbitrary[T]): Gen[T] = ev.arbitrary

  private val allScanners = Seq(Scanners.MySQLInnoDB(dummySmenv), Scanners.MySQL(dummySmenv),
                                Scanners.MicrosoftSQLServer2005(dummySmenv),
                                Scanners.MicrosoftSQLServer(dummySmenv),
                                Scanners.Postgres(dummySmenv),
                                Scanners.Vertica(dummySmenv), Scanners.SQLite(dummySmenv))
  private val allEmitters = {
    import SqlEmitter._
    Seq(mySqlInnoDBEmitter, mySqlEmitter, msSqlEmitter2005, msSqlEmitter,
        postgreSqlEmitter, verticaSqlEmitter, sqliteEmitter)
  }

  // Engine arbs
  implicit val backendArb: Arbitrary[SqlScanner] =
    Arbitrary(oneOf(allScanners))
  implicit val emitterArb: Arbitrary[SqlEmitter] =
    Arbitrary(oneOf(allEmitters))

  // SQL arbs
  val sqlBools = stdGen[Boolean] map (SqlBool(_))
  val sqlInts = stdGen[Int] map (SqlInt(_))
  val sqlOrders = oneOf(Seq(SqlAsc, SqlDesc))
  val litSqlExprs = oneOf(sqlBools, sqlInts) map (LitSqlExpr(_))

  /** Make `OverSqlExpr`s. */
  val overSqlExprs = for {
    i <- sqlInts map (LitSqlExpr(_))
    l <- nonEmptyListOf(for {
           b <- sqlBools map (LitSqlExpr(_))
           o <- sqlOrders
         } yield (b, o))
  } yield OverSqlExpr(i, l)

  /** Make FromTables exprs. */
  val fromTables = for {
    n <- nonEmptyAlphaStr
    a <- nonEmptyAlphaStr
    l <- nonEmptyListOf(nonEmptyAlphaStr)
  } yield FromTable(TableName(n), l.toSet.toList, Some(TableName(a)))

  private def trivialHeader(cols: Seq[ColumnName]): Header =
    cols.zip(Stream.continually(PrimT.IntT())).toMap

  /** Make `SqlJoinOn`s. */
  val joinOnExprs = for {
    left      <- fromTables
    right     <- fromTables
    joinColCt <- choose(1, left.cols.size min right.cols.size)
    joinLCols <- pick(joinColCt, left.cols)
    joinRCols <- pick(joinColCt, right.cols)
  } yield SqlJoinOn(left,
                    right,
                    joinLCols.zip(joinRCols).toSet)
}

object TestSqlEmitters extends Properties("emitSql") {
  import Prop._
  import SqlEmitterGens._

  implicit val overSqlExprArb = Arbitrary(overSqlExprs)
  implicit val joinOnExprArb = Arbitrary(joinOnExprs)

  property("only MS emitters use literal `over'") = forAll {
    (emitter: SqlEmitter, overexpr: OverSqlExpr) =>
      emitter.isInstanceOf[MsSqlEmitter] ==
      ("""(?s) over \(.*\)""".r
       findFirstIn overexpr.emitSql(emitter).run).isDefined
  }

  private def danglingTable(tname: String):
    scala.util.matching.Regex =
      (java.util.regex.Pattern.quote(tname) + """\.[^A-Za-z]""").r

  property("joinOn emitters distribute columns") = forAll {
    (joinOnExpr: SqlJoinOn, emitter: SqlEmitter) =>
      val sql = joinOnExpr.emitSql(emitter)
      (sql.run + " should make sense") |: (joinOnExpr match {
        case SqlJoinOn(FromTable(ltable, _, _),
                       FromTable(rtable, _, _),
                       _, _) =>
          Seq(ltable, rtable) forall { tablechoice =>
            danglingTable(tablechoice.name).
            findFirstIn(sql.run) match {
              case None => true
              case _    => false
            }
          }
        case _ => false
      })
  }

  private def exactMatches(r: scala.util.matching.Regex, s: String) =
    r.findPrefixMatchOf(s).map {m => m.start === 0 && m.end === s.size}.
      getOrElse(false)

  private def matchProp(r: scala.util.matching.Regex, s: String) =
    exactMatches(r, s) :| (""""%s" must match "%s"""" format (s, r))

  property("SQL emitted stays more or less the same") = forAll {
    (emitter: SqlEmitter) =>
      val idq = if ((emitter eq SqlEmitter.verticaSqlEmitter)
                    || (emitter eq SqlEmitter.sqliteEmitter))
        "" else "."
      Seq("""(?x)select\s(distinct\s)?\(.dbaquestions.\..a.\)\s.a.,
             \s\(.dbaquestions.\..n.\)\s.n.,
             \s\(.dbaquestions.\..q.\)\s.q.\sfrom
             \s.dbaquestions.\s.dbaquestions.\s
             where\s\(\(.dbaquestions.\..n.\)\s=\s\(?1\)?\)\s?"""
          -> SqlSelect(attrs=("nqa".map(_.toString)
                              .map{c=>c->ColumnSqlExpr(TableName("dbaquestions"),c)}.toMap),
                       sources=SourceList(FromTable(TableName("dbaquestions"), List("a","n","q"), Some(TableName("dbaquestions")))),
                       criteria=List(SqlEq(ColumnSqlExpr(TableName("dbaquestions"), "n"),
                                           LitSqlExpr(SqlInt(1))))),
          """(?x)select\s(distinct\s)?\(.yesiwilltable.\..yes.\)\s.yes.\sfrom\s.yesiwilltable."""
          -> SqlSelect(attrs=Map("yes" -> ColumnSqlExpr(TableName("yesiwilltable"), "yes")),
                       sources = SourceList(FromTable(TableName("yesiwilltable"), List("yes"), None)))).
      map {case (rs, sql) =>
        val r = rs.replaceAll("""(?<!\\)\.""", idq).r // hack out table/column quoting
        matchProp(r, sql.emitSql(emitter).run)
      }.
      foldLeft(true: Prop)(_ && _)
  }

  val if023 = {
    val x = ColumnValue("x", IntT())
    def num(n: Int) = OpLiteral(IntExpr(false, n))
    def eqx(n: Int) = Eq(x, num(n))
    If(Not(eqx(0)),
       If(eqx(2), num(2),
          If(eqx(3), num(3), Add(x, num(3)))),
       num(0))
  }

  property("if chains become cases") = secure {
    val b = Scanners.MicrosoftSQLServer(dummySmenv)
    val e = SqlEmitter.msSqlEmitter
    ("""(case when not (not (([bob].[x]) = (0))) then 0"""
     + """ when ([bob].[x]) = (2) then 2"""
     + """ when ([bob].[x]) = (3) then 3"""
     + """ else (([bob].[x]) + (3)) end)""") =?
       SqlExpr.compileOp(if023, ColumnSqlExpr(TableName("bob"), _))(e).emitSql(e).run
  }

  val sqliteTestLiteral : SqlQuery =
    LiteralSqlTable(
      NonEmptyList(
        Map( "a" -> LitSqlExpr(SqlInt(1))
           , "b" -> LitSqlExpr(SqlInt(2))
           )
      , Map( "a" -> LitSqlExpr(SqlInt(2))
           , "b" -> LitSqlExpr(SqlInt(1))
           )
      )
    )

  property("sqlite literal syntax valid") = secure {
    val e = SqlEmitter.sqliteEmitter
    val b = Scanners.SQLite(dummySmenv)
    val r = Runners.SQLite("jdbc:sqlite::memory:")

    val rawQuery = RawSql.raw("explain ") |+| sqliteTestLiteral.emitSql(e)

    r.run(DB.executeQuery(rawQuery))
    true
  }
}
