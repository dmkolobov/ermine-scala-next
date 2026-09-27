package com.clarifi.reporting
package relational

import java.sql.{ Connection, DriverManager }

import com.clarifi.machines.Process
import com.clarifi.reporting.backends.Scanners
import com.clarifi.reporting.PrimT._
import com.clarifi.reporting.Op.{ ColumnValue, OpLiteral }
import com.clarifi.reporting.Predicate.{ And, Atom, Eq, Gt, IsNull, Lt, Not, Or }
import com.clarifi.reporting.ermine.{ Runtime, Rel => RRel }
import com.clarifi.reporting.ermine.json.{ Request, Runner, RunnerConfig }

import scalaz.NonEmptyList
import scalaz.std.vector._

import org.scalacheck.{ Gen, Prop, Properties }
import org.scalacheck.Prop.{ Result => _, _ }

/** SQL audit (tracker/sql-audit/WORKLIST.md), area `rel`: the fixes in `Rel.scala`,
  * `Typer.scala`, `ReportingUtils.scala`, `Optimizer.scala` and `Lib.scala`'s relational
  * functions, each pinned by the finding's shrunk repro and covered by a property.
  * Relations are executed on an in-memory SQLite connection through `Scanners.SQLite`
  * (the differential oracle's idiom); Ermine-level shapes go through `ErmineFixture`.
  *
  *  - R1 (O-1/L-1/S-01): `JoinOn.bimap/subst/unquote` keep `mode`; an outer join under
  *    `letR`/`letRWithPK` and a mixed Rel/Mem outer join are outer joins.
  *  - R2 (O-7/S-02): `leftJoinOr`/`joinWithDefault` inside a `letR`/`groupBy` body type
  *    (the binder tags its quote with the bound header) instead of panicking.
  *  - R3 (S-03): `leftJoinOr r (relation [])` keeps the default columns.
  *  - R4 (D4): an outer join's NULL-filled side is nullable in the header; a `pivot`
  *    with a NULL default is nullable and reads back NULL instead of throwing.
  *  - R5 (O-6/S-25): `difference (filter p1 r) (filter p2 r)` is one filter, exact under
  *    three-valued logic (`ReportingUtils.notTrue`); `filterNEq`'s shape folds the same way.
  *  - R6 (O-9/S-30): `x == x` folds to TRUE only for a non-nullable operand.
  *  - R7 (O-10): two `aggregateByGroup`s coalesce into one GROUP BY only over
  *    non-nullable group columns.
  *  - R8 (S-20, D7): `groupBy k (sumBy c)` and friends lower to `AggregateByGroup`.
  *
  * Every pin FAILS on the pre-fix compiler; the pre-fix answer is named beside it.
  */
object TestSqlRel extends Properties("SQL audit, area rel (R1-R8)") {

  // ------------------------------------------------------------------ helpers

  type Rel = Relation[Nothing, Nothing]

  private def i(n: Int): PrimExpr = IntExpr(false, n)
  private def in(n: Int): PrimExpr = IntExpr(true, n)
  private val inull: PrimExpr = NullExpr(IntT(true))
  private def s(x: String): PrimExpr = StringExpr(false, x)
  private def kcol = ColumnValue("k", IntT(false))
  private def bcol = ColumnValue("b", IntT(true))

  private def lit(rows: Record*): Rel =
    SmallLit(NonEmptyList.nel(rows.head, scalaz.IList.fromList(rows.tail.toList)))
  private def mlit(rows: Record*): Mem[Nothing, Nothing] =
    Literal(NonEmptyList.nel(rows.head, scalaz.IList.fromList(rows.tail.toList)))
  private def proj(r: Rel, cols: (String, PrimT)*): Rel =
    Project(r, cols.map { case (c, t) => Attribute(c, t) -> (ColumnValue(c, t): Op) }.toMap)

  private lazy val scanner = Scanners.SQLite(SMEnv.dummySmenv)
  private lazy val conn: Connection = { Class.forName("org.sqlite.JDBC"); DriverManager.getConnection("jdbc:sqlite::memory:") }
  private val lock = new Object

  /** The rows `rel` delivers on SQLite, or the exception's text. */
  private def rows(rel: Rel): Either[String, Set[Record]] = lock.synchronized {
    try Right(scanner.scanRel[Vector[Record]](rel, Process((r: Record) => Vector(r)))(vectorMonoid[Record]).apply(conn).toSet)
    catch { case e: Throwable => Left(e.getClass.getName + ": " + String.valueOf(e.getMessage).take(400)) }
  }
  private def rowsOf(ext: Ext[Nothing, Nothing]): Either[String, Set[Record]] = lock.synchronized {
    try Right(scanner.collect(ext).apply(conn).toSet)
    catch { case e: Throwable => Left(e.getClass.getName + ": " + String.valueOf(e.getMessage).take(400)) }
  }
  private def sql(rel: Rel): String = lock.synchronized {
    try scanner.dumpRel(rel) catch { case e: Throwable => "<dumpRel threw " + e + ">" }
  }
  private def sqlOf(ext: Ext[Nothing, Nothing]): String = ext match {
    case ExtRel(r, _) => sql(r)
    case other => "<not a relation: " + other.getClass.getSimpleName + ">"
  }

  /** Rows compared by VALUE: `NullExpr` never equals `NullExpr` on this tree (S-18, the
    * prims area's P2) and the nullable flag a column decodes with is the header's. */
  private def norm(r: Record): Map[String, String] = r.map { case (k, v) => k -> (v match {
    case NullExpr(_) => "NULL"
    case IntExpr(_, n) => n.toString
    case DoubleExpr(_, x) => x.toString
    case StringExpr(_, x) => x
    case BooleanExpr(_, b) => b.toString
    case other => other.toString
  }) }

  private def delivers(rel: Rel, expected: Set[Record]): Prop = rows(rel) match {
    case Left(e)  => Prop.falsified :| ("threw " + e + "\nSQL:\n" + sql(rel))
    case Right(r) => (r.map(norm) ?= expected.map(norm)) :| ("SQL:\n" + sql(rel))
  }

  private def upper(x: String) = x.toUpperCase

  // ------------------------------------------------------------------ R1: JoinOn keeps its mode

  private val modes: Gen[JoinMode] = Gen.oneOf(JoinMode.Inner, JoinMode.Left, JoinMode.Right, JoinMode.Full)

  private def modeOf(r: Relation[_, _]): Option[JoinMode] = r match {
    case j: JoinOn[_, _] => Some(j.mode)
    case _ => None
  }

  property("R1: bimap, subst and unquote keep a JoinOn's mode") = forAll(modes) { m =>
    val j: Relation[Int, Int] = JoinOn(VarR(1), VarR(2), Set(("a", "b")), m)
    ((modeOf(j.map(x => x)) ?= Some(m)) :| "map (bimap)") &&
    ((modeOf(j.flatMap(VarR(_))) ?= Some(m)) :| "flatMap (subst)") &&
    ((modeOf(j.unquote[Int, Int](_ => None, _ => None)) ?= Some(m)) :| "unquote") &&
    // the optimizer's LetR path: fromScope then toScope
    ((modeOf(Relation.toScope(Relation.fromScope(j.map(x => (RPop(VarR(x)): RLevel[Int, Int]))))) ?= Some(m)) :| "fromScope/toScope")
  }

  // t1: k = 1, 2, 3; t2: k = 1, 2, 4
  private val t1 = lit(Map("k" -> i(1), "a" -> i(10)), Map("k" -> i(2), "a" -> i(20)), Map("k" -> i(3), "a" -> i(30)))
  private val t2rows = List(Map("k" -> i(1), "b" -> i(1)), Map("k" -> i(2), "b" -> i(2)), Map("k" -> i(4), "b" -> i(4)))
  private val t2 = lit(t2rows: _*)
  private def keys(ks: Int*): Set[Record] = ks.map(k => Map("k" -> i(k)): Record).toSet

  /** `letR t2 (x -> join t1 x)` under `mode`, projected to the key (the join key is never
    * NULL on any side the mode keeps, so the read is safe whatever the header says). */
  private def underLet(mode: JoinMode, pk: List[String] = Nil): Rel =
    proj(LetR(ExtRel(t2, ""), pk, JoinOn(VarR(RPop(t1)), VarR(RTop), Set(), mode)), "k" -> IntT(false))
  /** The mixed Rel/Mem form `LeftJoinE(ExtRel(t1), ExtMem(literal))` builds. */
  private def mixed(mode: JoinMode): Rel =
    proj(LetR(ExtMem(mlit(t2rows: _*)), Nil, JoinOn(VarR(RPop(t1)), VarR(RTop), Set(), mode)), "k" -> IntT(false))
  private def expectedKeys(mode: JoinMode): Set[Record] = mode match {
    case JoinMode.Inner => keys(1, 2)
    case JoinMode.Left  => keys(1, 2, 3)
    case JoinMode.Right => keys(1, 2, 4)
    case JoinMode.Full  => keys(1, 2, 3, 4)
  }

  property("R1 pin: an outer join under letR is an outer join (pre-fix: the inner join's 2 keys)") = secure {
    delivers(underLet(JoinMode.Left), keys(1, 2, 3)) &&
    delivers(underLet(JoinMode.Full), keys(1, 2, 3, 4)) &&
    delivers(underLet(JoinMode.Right), keys(1, 2, 4)) &&
    Prop(upper(sql(underLet(JoinMode.Left))).contains("LEFT")) :| ("no LEFT in " + sql(underLet(JoinMode.Left)))
  }

  property("R1 pin: letRWithPK and a Rel/Mem outer join keep the mode (pre-fix: inner)") = secure {
    delivers(underLet(JoinMode.Left, List("k")), keys(1, 2, 3)) &&
    delivers(mixed(JoinMode.Left), keys(1, 2, 3)) &&
    delivers(mixed(JoinMode.Full), keys(1, 2, 3, 4))
  }

  property("R1: every mode under letR, letRWithPK and beside a Mem delivers its keys") = forAll(modes) { m =>
    delivers(underLet(m), expectedKeys(m)) && delivers(underLet(m, List("k")), expectedKeys(m)) && delivers(mixed(m), expectedKeys(m))
  }

  // ------------------------------------------------------------------ R4: the typer's join header

  private val nullableOf: Gen[Boolean] = Gen.oneOf(true, false)

  property("R4: the NULL-filled side of an outer join is nullable; a shared key is typed by mode (Full: nullable if either side's is)") =
    forAll(modes, nullableOf, nullableOf, nullableOf) { (m, na, nb, nk) =>
      val left: Header = Map("k" -> IntT(nk), "a" -> IntT(na))
      val right: Header = Map("k" -> IntT(false), "b" -> IntT(nb))
      val h = Typer.relTyper(JoinOn(lit(Map("k" -> IntExpr(nk, 1), "a" -> IntExpr(na, 1))),
                                    lit(Map("k" -> i(1), "b" -> IntExpr(nb, 1))), Set(), m))
      val leftNull = m == JoinMode.Right || m == JoinMode.Full
      val rightNull = m == JoinMode.Left || m == JoinMode.Full
      val keyNull = m match {
        case JoinMode.Left => nk; case JoinMode.Right => false; case JoinMode.Full => nk; case JoinMode.Inner => false }
      h.fold(e => Prop.falsified :| e.toString, hdr =>
        ((hdr("k").nullable ?= keyNull) :| ("shared key under " + m)) &&
        ((hdr("a").nullable ?= (na || leftNull)) :| "left-only column") &&
        ((hdr("b").nullable ?= (nb || rightNull)) :| "right-only column") &&
        ((Typer.joinHeader(left, right, m) ?= hdr) :| "joinHeader agrees with relTyper"))
    }

  property("R4b-Full pin: a NULL left key under a FULL join survives as a row whose key is NULL, so the key is nullable (pre-fix: typed non-nullable)") = secure {
    val j: Rel = JoinOn(lit(Map("k" -> inull, "a" -> i(1))),
                        lit(Map("k" -> in(1), "b" -> i(1)), Map("k" -> in(2), "b" -> i(2))), Set(), JoinMode.Full)
    val h = Typer.relTyper(j).fold(e => Map[String, PrimT](), x => x)
    ((h.get("k").map(_.nullable) ?= Some(true)) :| ("header: " + h)) &&
    ((Typer.joinHeader(Map("k" -> IntT(false)), Map("k" -> IntT(true)), JoinMode.Full).get("k").map(_.nullable) ?= Some(true)) :| "right side nullable too") &&
    ((Typer.joinHeader(Map("k" -> IntT(true)), Map("k" -> IntT(false)), JoinMode.Inner).get("k").map(_.nullable) ?= Some(false)) :| "inner match is never NULL") &&
    delivers(proj(j, "k" -> IntT(true)), Set(Map("k" -> inull), Map("k" -> in(1)), Map("k" -> in(2))))
  }

  private val pivotIn = lit(Map("id" -> s("a"), "m" -> s("x"), "v" -> i(1)),
                            Map("id" -> s("b"), "m" -> s("x"), "v" -> i(3)),
                            Map("id" -> s("b"), "m" -> s("y"), "v" -> i(4)))
  private def pivotWith(dflt: PrimExpr): Rel =
    PivotR(pivotIn, Set("m"), Set("v"), false, Map(
      "xs" -> ((Map("m" -> s("x")), (ColumnValue("v", IntT(false)): Op), dflt)),
      "ys" -> ((Map("m" -> s("y")), (ColumnValue("v", IntT(false)): Op), dflt))))

  property("R4 pin: a pivot with a NULL default is nullable and reads NULL where a key is missing (pre-fix: 'Unexpected NULL')") = secure {
    val h = Typer.relTyper(pivotWith(inull)).fold(e => Map[String, PrimT](), x => x)
    ((h.get("ys").map(_.nullable) ?= Some(true)) :| ("header: " + h)) &&
    ((Typer.relTyper(pivotWith(i(-1))).fold(e => (None: Option[Boolean]), x => x.get("ys").map(_.nullable)) ?= Some(false)) :| "a non-NULL default stays non-nullable") &&
    delivers(pivotWith(inull), Set(Map("id" -> s("a"), "xs" -> in(1), "ys" -> NullExpr(IntT(true))),
                                   Map("id" -> s("b"), "xs" -> in(3), "ys" -> in(4))))
  }

  // ------------------------------------------------------------------ R5: difference of two filters

  private def nrow(k: Int, b: Option[Int]): Record = Map("k" -> i(k), "b" -> b.map(in).getOrElse(inull))
  private val nr = lit(nrow(1, Some(1)), nrow(2, None), nrow(3, Some(9)), nrow(0, Some(9)))

  property("R5 pin: difference (filter k>1) (filter b>5) keeps the row whose b is NULL (pre-fix: dropped) and is one filter") = secure {
    val d = Minus(Filter(nr, Gt(kcol, OpLiteral(i(1)))), Filter(nr, Gt(bcol, OpLiteral(i(5)))))
    val text = sql(d)
    delivers(d, Set(nrow(2, None))) &&
    (Prop(!upper(text).contains("EXCEPT")) :| ("EXCEPT in " + text)) &&
    (Prop(d.isInstanceOf[Filter[_, _]]) :| ("not a Filter: " + d))
  }

  property("R5 pin: filterNEq's shape r MINUS (r JOIN {b = 9}) is one filter and keeps the NULL row (pre-fix: two scans + EXCEPT)") = secure {
    val d: Rel = MinusI(nr, JoinOn(nr, lit(Map("b" -> in(9))), Set(), JoinMode.Inner))
    val text = sql(d)
    val two: Rel = MinusI(nr, JoinOn(nr, lit(Map("b" -> in(9)), Map("b" -> in(1))), Set(), JoinMode.Inner))
    delivers(d, Set(nrow(1, Some(1)), nrow(2, None))) &&
    (Prop(!upper(text).contains("EXCEPT")) :| ("EXCEPT in " + text)) &&
    (Prop(text.toLowerCase.contains("is null")) :| ("no IS NULL guard in " + text)) &&
    delivers(two, Set(nrow(2, None))) &&
    (Prop(!upper(sql(two)).contains("EXCEPT")) :| ("EXCEPT in " + sql(two)))
  }

  /** A three-valued reference: `Some(true/false)` or `None` for UNKNOWN. */
  private def ev3(p: Predicate, r: Record): Option[Boolean] = {
    def v(o: Op): Option[Int] = o match {
      case ColumnValue(c, _) => r(c) match { case IntExpr(_, n) => Some(n); case _ => None }
      case OpLiteral(IntExpr(_, n)) => Some(n)
      case _ => None
    }
    def cmp(l: Op, x: Op)(f: (Int, Int) => Boolean) = for (a <- v(l); b <- v(x)) yield f(a, b)
    p match {
      case Atom(t) => Some(t)
      case Lt(l, x) => cmp(l, x)(_ < _)
      case Gt(l, x) => cmp(l, x)(_ > _)
      case Eq(l, x) => cmp(l, x)(_ == _)
      case IsNull(o) => Some(v(o).isEmpty)
      case Not(q) => ev3(q, r).map(!_)
      case And(a, b) => (ev3(a, r), ev3(b, r)) match {
        case (Some(false), _) | (_, Some(false)) => Some(false)
        case (Some(true), Some(true)) => Some(true)
        case _ => None
      }
      case Or(a, b) => (ev3(a, r), ev3(b, r)) match {
        case (Some(true), _) | (_, Some(true)) => Some(true)
        case (Some(false), Some(false)) => Some(false)
        case _ => None
      }
      case _ => None
    }
  }

  private val genOp: Gen[Op] = Gen.frequency(
    (3, Gen.const(kcol)), (3, Gen.const(bcol)),
    (1, Gen.choose(-1, 3).map(n => OpLiteral(i(n)))),
    (1, Gen.const(OpLiteral(inull))))
  private def genPred(depth: Int): Gen[Predicate] =
    if (depth <= 0) Gen.oneOf[Predicate](
      for (l <- genOp; r <- genOp) yield Lt(l, r),
      for (l <- genOp; r <- genOp) yield Gt(l, r),
      for (l <- genOp; r <- genOp) yield Eq(l, r),
      genOp.map(IsNull(_)),
      Gen.oneOf[Predicate](Atom(true), Atom(false)))
    else Gen.frequency[Predicate](
      (2, genPred(0)),
      (1, genPred(depth - 1).map(Not(_))),
      (1, for (a <- genPred(depth - 1); b <- genPred(depth - 1)) yield And(a, b)),
      (1, for (a <- genPred(depth - 1); b <- genPred(depth - 1)) yield Or(a, b)))
  private val genRow: Gen[Record] =
    for (k <- Gen.choose(0, 3); b <- Gen.option(Gen.choose(0, 3))) yield nrow(k, b)

  property("R5: notTrue(p) is TRUE exactly when p is not TRUE, and never UNKNOWN") =
    forAll(genPred(3), genRow) { (p, r) =>
      ReportingUtils.notTrue(p) match {
        case None => Prop.falsified :| "notTrue gave up on a predicate without Funtest"
        case Some(np) => (ev3(np, r) ?= Some(ev3(p, r) != Some(true))) :| ("notTrue = " + np)
      }
    }

  property("R5: difference of two filters over random NULLs delivers the set difference") =
    forAll(Gen.listOfN(6, genRow), genPred(2), genPred(2)) { (rs, p1, p2) =>
      val r: Rel = if (rs.isEmpty) RelEmpty(Map("k" -> IntT(false), "b" -> IntT(true))) else lit(rs: _*)
      val d = Minus(Filter(r, p1), Filter(r, p2))
      val expected = rs.toSet.filter(x => ev3(p1, x) == Some(true) && ev3(p2, x) != Some(true))
      delivers(d, expected)
    }

  // ------------------------------------------------------------------ R6: x == x

  property("R6: x == x folds to TRUE only for an operand that cannot be NULL") = forAll(nullableOf) { n =>
    val c = ColumnValue("x", IntT(n))
    val folded = ReportingUtils.simplifyPredicate(Eq(c, c))
    if (n) (folded ?= Eq(c, c)) :| "nullable column must not fold"
    else (folded ?= Atom(true)) :| "non-nullable column folds"
  }

  property("R6 pin: NULL == NULL never folds to TRUE, whatever the literal's declared type (with P2, NullExpr equals NullExpr)") = secure {
    val nulls = List(NullExpr(IntT(true)), NullExpr(IntT(false)), NullExpr(StringT(0, true)))
    Prop.all(nulls.map { n =>
      val l: Op = OpLiteral(n)
      (ReportingUtils.simplifyPredicate(Eq(l, l)) ?= Eq(l, l)) :| ("folded: " + n)
    }: _*) &&
    ((ReportingUtils.simplifyPredicate(Eq(OpLiteral(i(1)), OpLiteral(i(1)))) ?= Atom(true)) :| "1 == 1 still folds")
  }

  property("R6 pin: filter (inl == inl) over a NULL drops the row, as SQL does (pre-fix: kept)") = secure {
    val c = ColumnValue("inl", IntT(true))
    delivers(Filter(lit(Map("inl" -> inull)), Eq(c, c)), Set()) &&
    delivers(Filter(lit(Map("inl" -> in(1))), Eq(c, c)), Set(Map("inl" -> in(1)))) &&
    delivers(Filter(lit(Map("ia" -> i(1))), Eq(ColumnValue("ia", IntT(false)), ColumnValue("ia", IntT(false)))), Set(Map("ia" -> i(1))))
  }

  // ------------------------------------------------------------------ R10: a NULL constant is not substituted

  property("R10: a column known to be NULL is not substituted into the predicate (pre-fix: an untyped NULL literal)") = secure {
    val tn = ColumnValue("tn", DateT(true))
    val truth = Reflexivity.literal(NonEmptyList.nel[Record](Map("tn" -> NullExpr(DateT(true))), scalaz.IList.empty))
    val p = Eq(tn, Op.If(Lt(tn, tn), tn, tn))
    val simplified = ReportingUtils.simplifyPredicate(p, truth)
    (Prop(simplified.columnReferences.contains("tn")) :| ("tn substituted away: " + simplified)) &&
    // a non-NULL constant is still substituted
    ((ReportingUtils.simplifyPredicate(Gt(kcol, OpLiteral(i(0))), Reflexivity.literal(NonEmptyList.nel[Record](Map("k" -> i(1)), scalaz.IList.empty))) ?= Gt(OpLiteral(i(1)), OpLiteral(i(0)))) :| "k = 1 is substituted into k > 0")
  }

  // ------------------------------------------------------------------ R7: coalescing two GROUP BYs

  private def agg(r: Rel, keyT: PrimT, name: String, f: AggFunc): AggregateByGroup[Nothing, Nothing] =
    AggregateByGroup(r, Map(Attribute("k", keyT) -> (ColumnValue("k", keyT): Op)), List((Attribute(name, IntT(false)), f)), List(ColumnValue("k", keyT)))

  property("R7: two aggregateByGroups coalesce into one GROUP BY only over non-nullable group columns") = forAll(nullableOf) { n =>
    val t = IntT(n)
    val r = lit(Map("k" -> IntExpr(n, 1), "a" -> i(1)))
    val j = Join(agg(r, t, "s", AggFunc.Sum(ColumnValue("a", IntT(false)))), agg(r, t, "x", AggFunc.Max(ColumnValue("a", IntT(false)))))
    if (n) Prop(j.isInstanceOf[JoinOn[_, _]]) :| ("nullable key coalesced: " + j)
    else Prop(j.isInstanceOf[AggregateByGroup[_, _]]) :| ("non-nullable key not coalesced: " + j)
  }

  property("R7 pin: with a NULL group key the join of two group results drops the NULL group, as a natural join does (pre-fix: kept)") = secure {
    val r = lit(Map("k" -> in(1), "a" -> i(1)), Map("k" -> in(1), "a" -> i(3)), Map("k" -> inull, "a" -> i(5)))
    val j = Join(agg(r, IntT(true), "s", AggFunc.Sum(ColumnValue("a", IntT(false)))), agg(r, IntT(true), "x", AggFunc.Max(ColumnValue("a", IntT(false)))))
    delivers(j, Set(Map("k" -> in(1), "s" -> i(4), "x" -> i(3))))
  }

  // ------------------------------------------------------------------ Ermine level: R2, R3, R8

  private val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  private val onlyTest = Map("Test" -> fx.all)

  private val probes =
    """import List using empty_Bracket; cons_Bracket
      |import Native.Relation using letR
      |import Relation
      |import Relation.Row hiding empty_Bracket; cons_Bracket
      |
      |field k : Int
      |field s : String
      |field u : String
      |field region : String
      |field amount : Double
      |field z : Int
      |
      |r1 = relation [{k = 1, s = "a"}, {k = 2, s = "b"}, {k = 3, s = "c"}]
      |rx = relation [{k = 1, u = "one"}, {k = 2, u = "two"}]
      |
      |-- R2: header-inspecting helpers on a let-bound variable
      |letLeftOr  = letR r1 (r -> leftJoinOr r rx {u = "?"})
      |letDefault = letRWithPK {k} rx (x -> joinWithDefault u "?" r1 x)
      |matLeftOr  = leftJoinOr (materialize r1) rx {u = "?"}
      |letHeader  = letR r1 (r -> relationWithHeader (rheader r) [])
      |grpLeftOr  = groupBy {k} (m -> leftJoinOr m (asMem (relation [{s = "a", u = "x"}])) {u = "?"}) r1
      |
      |-- R4b: an unsafe outer join's result (u nullable now) beside a plain relation
      |lj = unsafeLeftJoin r1 rx
      |unionLj = union lj (relation [{k = 3, s = "c", u = "three"}])
      |joinLj  = join lj (relation [{u = "one", z = 1}])
      |
      |-- R3: an outer join against the headerless empty relation
      |emptyLeftOr  = leftJoinOr r1 (relation []) {u = "?"}
      |emptyDefault = joinWithDefault u "?" r1 (relation [])
      |
      |-- R8: groupBy with exactly one aggregate per group
      |sales = relation
      |  [ { region = "north", amount = 1200.5 }, { region = "north", amount = 840.0 }
      |  , { region = "south", amount = 615.75 }, { region = "east", amount = 75.5 } ]
      |bySum   = groupBy {region} (sumBy amount) sales
      |byCount = groupBy {region} count sales
      |byMax   = groupBy {region} (maxBy amount) sales
      |byMin   = groupBy {region} (minBy_A amount) sales
      |byMean  = groupBy {region} (meanBy amount) sales
      |byProj  = groupBy {region} (m -> project {amount} m) sales
      |""".stripMargin

  private def ext(binding: String): Either[String, Ext[Nothing, Nothing]] =
    try fx.defAndEval(probes, binding, onlyTest).whnf match {
      case RRel(e) => Right(e)
      case other => Left("not a relation: " + other)
    } catch { case e: Throwable => Left(e.getClass.getName + ": " + String.valueOf(e.getMessage).take(300)) }

  private def optimized(binding: String): Either[String, Ext[Nothing, Nothing]] =
    ext(binding).right.flatMap(e => try Right(Typer.closedExt(Optimizer.optimize(e)).out)
                                   catch { case x: Throwable => Left(x.getClass.getName + ": " + String.valueOf(x.getMessage).take(300)) })

  private def ermineDelivers(binding: String, expected: Set[Record]): Prop = optimized(binding) match {
    case Left(e) => Prop.falsified :| (binding + " " + e)
    case Right(e) => rowsOf(e) match {
      case Left(err) => Prop.falsified :| (binding + " threw " + err + "\nSQL:\n" + sqlOf(e))
      case Right(rs) => (rs.map(norm) ?= expected.map(norm)) :| (binding + " SQL:\n" + sqlOf(e))
    }
  }

  private def kRow(k: Int, s: String, u: String): Record = Map("k" -> i(k), "s" -> StringExpr(false, s), "u" -> StringExpr(false, u))
  private val threeWithDefault = Set(kRow(1, "a", "one"), kRow(2, "b", "two"), kRow(3, "c", "?"))

  property("R2 pin: leftJoinOr / joinWithDefault / rheader inside a letR body type and run (pre-fix: 'Asked for the header of a quote')") = secure {
    ermineDelivers("letLeftOr", threeWithDefault) &&
    ermineDelivers("letDefault", threeWithDefault) &&
    ermineDelivers("matLeftOr", threeWithDefault) &&
    ermineDelivers("letHeader", Set())
  }

  property("R2 pin: leftJoinOr inside a groupBy body types (pre-fix: panic)") = secure {
    ext("grpLeftOr") match {
      case Left(e) => Prop.falsified :| e
      case Right(e) => Prop(e.isInstanceOf[ExtMem[_, _]]) :| ("a Mem was expected: " + e)
    }
  }

  property("R3 pin: leftJoinOr r (relation []) keeps the default column on every row (pre-fix: 'nonexistent column (u)')") = secure {
    val all = Set(kRow(1, "a", "?"), kRow(2, "b", "?"), kRow(3, "c", "?"))
    ermineDelivers("emptyLeftOr", all) && ermineDelivers("emptyDefault", all)
  }

  private def headerOf(binding: String): Either[String, Header] =
    ext(binding).right.flatMap(e => try Right(Typer.closedExt(Optimizer.optimize(e)).header)
                                    catch { case x: Throwable => Left(x.getClass.getName + ": " + String.valueOf(x.getMessage).take(300)) })

  property("R4b pin: union / join of an unsafeLeftJoin result with a non-nullable twin column types (pre-R4b: 'Cannot union columns' / 'mismatching column types')") = secure {
    (headerOf("unionLj") match {
      case Left(e) => Prop.falsified :| ("unionLj " + e)
      case Right(h) => ((h.get("u").map(_.nullable) ?= Some(true)) :| ("union header: " + h)) &&
                       ((h.get("k").map(_.nullable) ?= Some(false)) :| ("union header: " + h))
    }) &&
    (headerOf("joinLj") match {
      case Left(e) => Prop.falsified :| ("joinLj " + e)
      case Right(h) => ((h.get("u").map(_.nullable) ?= Some(false)) :| ("join header (inner on u: a match is not NULL): " + h)) &&
                       ((h.get("z").map(_.nullable) ?= Some(false)) :| ("join header: " + h))
    }) &&
    ermineDelivers("joinLj", Set(Map("k" -> i(1), "s" -> s("a"), "u" -> s("one"), "z" -> i(1))))
  }

  property("R4b: union types a column nullable iff either side is; a base-type difference is still an error") = forAll(nullableOf, nullableOf) { (na, nb) =>
    val top: Header = Map("k" -> IntT(false), "u" -> StringT(0, na))
    val bottom: Header = Map("k" -> IntT(false), "u" -> StringT(0, nb))
    ((Typer.unionHeader(top, bottom).map(_("u").nullable) ?= Some(na || nb)) :| "nullable iff either") &&
    ((Typer.unionHeader(top, Map("k" -> IntT(false), "u" -> IntT(nb))) ?= None) :| "base types differ") &&
    ((Typer.unionHeader(top, Map("k" -> IntT(false))) ?= None) :| "columns differ") &&
    (Typer.relTyper(Union(lit(Map("k" -> i(1), "u" -> StringExpr(na, "a"))), lit(Map("k" -> i(2), "u" -> StringExpr(nb, "b")))))
       .fold(e => Prop.falsified :| e.toString, h => (h("u").nullable ?= (na || nb)) :| "relTyper agrees"))
  }

  /** The relational `AggregateByGroup` under the Mem `groupBy` answers, if it did (R8). */
  private def groupedInSql(binding: String): Either[String, (AggregateByGroup[Nothing, Nothing], String)] = ext(binding) match {
    case Left(e) => Left(e)
    case Right(ExtMem(EmbedMem(ExtRel(a@AggregateByGroup(_, _, _, _), db)))) => Right((a, db))
    case Right(other) => Left(binding + " lowered to " + other.getClass.getSimpleName + ": " + other)
  }

  private def d(x: Double): PrimExpr = DoubleExpr(false, x)
  private def region(r: String, col: String, v: PrimExpr): Record = Map("region" -> s(r), col -> v)

  property("R8 pin: groupBy k (sumBy/count/maxBy/minBy/meanBy c) over a relation is one GROUP BY in SQL (pre-fix: GroupByM, every row fetched)") = secure {
    def check(binding: String, aggName: String, expected: Set[Record], isAgg: AggFunc => Boolean): Prop = groupedInSql(binding) match {
      case Left(e) => Prop.falsified :| e
      case Right((a, _)) =>
        ((a.aggs.map(_._1.name) ?= List(aggName)) :| (binding + " aggregate column")) &&
        (Prop(isAgg(a.aggs.head._2)) :| (binding + " aggregate function: " + a.aggs.head._2)) &&
        ((a.group.map(_.col) ?= List("region")) :| (binding + " group columns")) &&
        (Prop(upper(sql(a)).contains("GROUP BY")) :| (binding + " SQL: " + sql(a))) &&
        delivers(a, expected)
    }
    check("bySum", "amount", Set(region("north", "amount", d(2040.5)), region("south", "amount", d(615.75)), region("east", "amount", d(75.5))),
          { case AggFunc.Sum(_) => true; case _ => false }) &&
    check("byCount", "Count", Set(region("north", "Count", i(2)), region("south", "Count", i(1)), region("east", "Count", i(1))),
          { case AggFunc.Count => true; case _ => false }) &&
    check("byMax", "amount", Set(region("north", "amount", d(1200.5)), region("south", "amount", d(615.75)), region("east", "amount", d(75.5))),
          { case AggFunc.Max(_) => true; case _ => false }) &&
    check("byMin", "amount", Set(region("north", "amount", d(840.0)), region("south", "amount", d(615.75)), region("east", "amount", d(75.5))),
          { case AggFunc.Min(_) => true; case _ => false }) &&
    check("byMean", "amount", Set(region("north", "amount", d(1020.25)), region("south", "amount", d(615.75)), region("east", "amount", d(75.5))),
          { case AggFunc.Avg(_) => true; case _ => false })
  }

  property("R8: a groupBy whose body is not one aggregate still groups in memory") = secure {
    ext("byProj") match {
      case Left(e) => Prop.falsified :| e
      case Right(ExtMem(GroupByM(_, key, _))) => (key.map(_.name) ?= List("region")) :| "group key"
      case Right(other) => Prop.falsified :| ("expected GroupByM, got " + other)
    }
  }

  // ------------------------------------------------------------------ R8 evidence: the FetchTopN document, groupBy vs aggregateByGroup

  private val exampleRoot = "core/src/test/resources/doc"
  private val genRoot: java.io.File = { val f = new java.io.File("core/target/sql-rel-modules"); f.mkdirs(); f }

  /** `FetchTopN` with `byRegion` written as the pre-F-1 `groupBy {region} (sumBy amount)`. */
  private lazy val groupByModule: String = {
    val src = scala.io.Source.fromFile(new java.io.File(exampleRoot, "FetchTopN.e"), "UTF-8")
    val text = try src.mkString finally src.close()
    val marker = "byRegion : [region, amount]\nbyRegion = aggregateByGroup_Aggregate (sum_Aggregate amount) {region} amount sales\n"
    require(text.contains(marker), "FetchTopN.e no longer defines byRegion as expected")
    val rewritten = text.replace("module FetchTopN where", "module RelGroupByTopN where")
                        .replace(marker, "byRegion = groupBy {region} (sumBy amount) sales\n")
    val out = new java.io.OutputStreamWriter(new java.io.FileOutputStream(new java.io.File(genRoot, "RelGroupByTopN.e")), "UTF-8")
    try out.write(rewritten) finally out.close()
    "RelGroupByTopN"
  }

  private lazy val runner: Runner = new Runner(RunnerConfig(
    roots = List(genRoot.getPath, exampleRoot), scanner = Scanners.SQLite(SMEnv.dummySmenv), ttlMillis = 600000L))

  private def traced(module: String): (Either[String, String], RenderTrace.Snapshot) = {
    val t = new RenderTrace()
    val out = new java.lang.StringBuilder
    t.start()
    val res = runner.renderText(module, "report", "{\"" + Request.Params + "\":{\"keep\":2}}", out, t) match {
      case Left(e) => Left(e.toString); case Right(_) => Right(out.toString) }
    t.finish()
    (res, t.snapshot())
  }

  property("R8 evidence: FetchTopN with groupBy {region} (sumBy amount) renders the same document as with aggregateByGroup and reads 4 rows, not 8") = secure {
    val gb = groupByModule
    val (ref, refTrace) = traced("FetchTopN")
    val (got, gotTrace) = traced(gb)
    def byRegion(sn: RenderTrace.Snapshot) = sn.queries.find(_.path == "$.fetch[1]")
    (ref, got) match {
      case (Right(a), Right(b)) =>
        ((b.replace(gb, "FetchTopN") ?= a) :| "documents differ") &&
        ((byRegion(gotTrace).map(_.rowsRead) ?= Some(4L)) :| ("groupBy read " + byRegion(gotTrace).map(_.rowsRead) + " rows; pre-fix 8 (every sale)")) &&
        ((byRegion(refTrace).map(_.rowsRead) ?= Some(4L)) :| "aggregateByGroup reads 4 rows") &&
        (byRegion(gotTrace).flatMap(_.sql).map(upper).exists(x => x.contains("GROUP BY") && x.contains("SUM(")) :| ("no GROUP BY in " + byRegion(gotTrace).flatMap(_.sql)))
      case (a, b) => Prop.falsified :| ("render failed: FetchTopN=" + a.left.getOrElse("ok") + " groupBy=" + b.left.getOrElse("ok"))
    }
  }
}
