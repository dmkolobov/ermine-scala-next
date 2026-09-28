package com.clarifi.reporting
package relational

import java.sql.{ Connection, DriverManager }
import java.util.Date

import com.clarifi.machines.Process
import com.clarifi.reporting.backends.Scanners
import com.clarifi.reporting.PrimT._
import com.clarifi.reporting.SortOrder.{ Asc, Desc }
import com.clarifi.reporting.util.YMDTriple

import scalaz.NonEmptyList
import scalaz.std.vector._

import org.scalacheck.{ Gen, Prop, Properties, Shrink, Test }
import org.scalacheck.Prop.{ Result => _, _ }

/** SQL audit, role `oracle` (tracker/sql-audit/brief-oracle.md): a differential test of
  * the SQL compiler.  Random `Relation[Nothing, Nothing]` trees over small typed
  * literals are evaluated three ways -- a plain Scala reference interpreter in this
  * file (`SqlDifferential.Ref`), `Scanners.SQLite` on an in-memory database, and
  * `Scanners.MicrosoftSQLServer` on the live server when `ERMINE_DB_*` is set -- and
  * every disagreement is a finding (`tracker/sql-audit/FINDINGS-oracle.md`).
  *
  * The reference is the SQL a relation SHOULD produce: a relation is a set (dedupe at
  * every step), predicates use SQL three-valued logic (a comparison with NULL is
  * UNKNOWN, a filter keeps only TRUE), aggregates ignore NULLs and an ungrouped aggregate
  * over an empty input follows decision D2 (WORKLIST.md): SUM answers its typed zero and
  * COUNT 0, AVG/MIN/MAX answer NO row; a grouped aggregate answers no rows (an absent
  * group is absent).  Expressions delegate to `Op.eval` node by node with NULL propagated
  * first, so the test is about relational structure, not arithmetic.
  *
  * HOW TO ADD A CONSTRUCTOR TO THE GENERATOR.  `SqlDifferential.Gens.genRel` is a
  * `Gen.frequency` over one generator per constructor, each answering `(Header, rel)`
  * with the header tracked by hand (and checked against `Typer` afterwards: a
  * mismatch is a discard, counted).  Write `genFoo(depth, leaf)` next to the others,
  * building its children with `genRel(depth - 1, leaf)`, add it to the frequency
  * table, add the evaluation case to `Ref.eval`, add its children to
  * `SqlDifferential.children` (so shrinking can descend into it) and to
  * `rebuild` (so shrinking can drop literal rows under it).  If the constructor
  * belongs to a known disagreement class, gate it with `enabled("<class>")` so
  * `-Dermine.test.sqldiff.<class>=true` re-enables it; every exclusion is a ticket
  * in the findings file.
  *
  * DISAGREEMENT CLASSES.  Every class the audit's implementers closed is in `fixed` and
  * is generated and pinned unconditionally (landing, 2026-09-27): letOuter eqSelf
  * nullConstSubst keyword nestedJoinRight limitOffsetOnly ifNestedConsequent concatNull
  * letTemp emptyAgg sumEmpty orderDupExpr orderByConstExpr decimalLiteral groupByConst
  * dupLit setOpPrecedence outerJoinInlinedExpr limitTwoRowsDistinct projectNonInjective
  * fullJoinNullKey limitOneRowOffset projectOverAggConst outerNull.  The one class still
  * excluded is `mixedCase` (O-23): strings are compared case-insensitively in memory and
  * in constant folding, byte-wise on SQLite; the collation is the user's decision (D9),
  * so it stays behind `-Dermine.test.sqldiff.mixedCase=true`.
  *
  * Not covered, on purpose: `MemoR` creates a PERSISTENT `MemoHash_...` table (the
  * audit uses ErmineSales read-only), `PivotR`, `TableProc`, `Table` (needs schema),
  * window functions, `Funcall`, `DateAdd`/`DateDiff` (the SQLite emitter has no
  * dateadd), `Cast`.
  */
object SqlDifferential {

  // ------------------------------------------------------------------ flags

  /** `-Dermine.test.sqldiff.<cls>=true` re-enables an excluded disagreement class. */
  def enabled(cls: String): Boolean =
    sys.props.get("ermine.test.sqldiff." + cls).exists(_.trim == "true")

  /** The classes the SQL audit's implementers closed (WORKLIST.md items in brackets):
    * always generated and always pinned, on both backends, whatever the flags say.
    * `mixedCase` is NOT here (decision D9: the collation call is the user's). */
  val fixed: Set[String] = Set(
    "letOuter",                // R1
    "eqSelf",                  // R6
    "nullConstSubst",          // R10
    "keyword",                 // E4
    "nestedJoinRight",         // E4
    "limitOffsetOnly",         // E5
    "ifNestedConsequent",      // E15
    "concatNull",              // E17
    "letTemp",                 // E16 + C7
    "emptyAgg",                // E10/E22 + C6
    "sumEmpty",                // C6 (D2) + E22
    "orderDupExpr",            // E23
    "orderByConstExpr",        // E23
    "decimalLiteral",          // E24
    "groupByConst",            // E21
    "dupLit",                  // C19 + E13
    "setOpPrecedence",         // C1 (D5)
    "outerJoinInlinedExpr",    // C3
    "limitTwoRowsDistinct",    // C4
    "projectNonInjective",     // C15
    "fullJoinNullKey",         // C16
    "limitOneRowOffset",       // C17
    "projectOverAggConst",     // C18
    "outerNull")               // R4 + C22 (D4)

  /** A class is exercised when its flag is set or the audit closed it. */
  def active(cls: String): Boolean = enabled(cls) || fixed(cls)

  /** `-Dermine.test.sqldiff.n=<int>` overrides minSuccessfulTests. */
  def minTests(default: Int): Int =
    sys.props.get("ermine.test.sqldiff.n").flatMap(s => scala.util.Try(s.trim.toInt).toOption).getOrElse(default)

  // ------------------------------------------------------------------ the value domain

  type Rel = Relation[Nothing, Nothing]
  type Rows = List[Record]

  final case class Col(name: String, t: PrimT)

  /** Every literal column has ONE type across the whole test, so natural joins and
    * unions between independently generated subtrees type-check by construction. */
  val cols: List[Col] = List(
    Col("ia", IntT(false)), Col("ib", IntT(false)), Col("inl", IntT(true)),   // not "in": finding O-6
    Col("da", DoubleT(false)), Col("dn", DoubleT(true)),
    Col("sa", StringT(0, false)), Col("sn", StringT(0, true)),
    Col("ba", BooleanT(false)),
    Col("ta", DateT(false)), Col("tn", DateT(true)))

  val freshNames: List[String] = List("p1", "p2", "p3", "p4", "p5", "p6")

  private val ints    = List(-2, -1, 0, 1, 2, 3)
  private val dates: List[Date] =
    List(YMDTriple(2023, 12, 31), YMDTriple(2024, 1, 1), YMDTriple(2024, 1, 2), YMDTriple(2024, 2, 29))

  /** `decimal`: a double literal is DECIMAL on SQL Server (O-21), so without the class
    * every double has one decimal place (one scale, nothing for a UNION or SUM to round).
    * `mixed`: lower case only unless `mixedCase` (O-23): SQLite compares strings
    * byte-wise, SQL Server under a case-insensitive collation, Ermine lower-cases. */
  def genValue(t: PrimT, decimal: Boolean = true, mixed: Boolean = false): Gen[PrimExpr] = {
    val n = t.nullable
    val doubles = if (decimal) List(-1.5, 0.0, 0.5, 1.0, 2.25, 3.0) else List(-1.5, 0.0, 0.5, 1.0, 3.0)
    val strings = List("a", "b", "c d", "", "x") ++ (if (mixed) List("B") else Nil)
    val nonNull: Gen[PrimExpr] = t match {
      case IntT(_)       => Gen.oneOf(ints).map(IntExpr(n, _))
      case DoubleT(_)    => Gen.oneOf(doubles).map(DoubleExpr(n, _))
      case StringT(_, _) => Gen.oneOf(strings).map(StringExpr(n, _))
      case BooleanT(_)   => Gen.oneOf(true, false).map(BooleanExpr(n, _))
      case DateT(_)      => Gen.oneOf(dates).map(DateExpr(n, _))
      case other         => sys.error("no generator for " + other)
    }
    if (n) Gen.frequency((3, nonNull), (1, Gen.const(NullExpr(t)))) else nonNull
  }

  def baseName(t: PrimT): String = t.name
  def isNumeric(t: PrimT): Boolean = t match { case IntT(_) | DoubleT(_) => true; case _ => false }

  // ------------------------------------------------------------------ profiles

  /** The disagreement classes a backend does NOT exhibit, so its generator keeps
    * producing them (more coverage per backend); every other class stays excluded until
    * `-Dermine.test.sqldiff.<class>=true`. */
  object Profile {
    /** SQLite: real doubles, each set-operation arm wrapped, a literal is a union of
      * selects (dedupes), NULL aggregates and duplicate ORDER BY expressions accepted. */
    val sqlite: Set[String] = Set("decimalLiteral", "setOpPrecedence", "dupLit", "emptyAgg", "orderDupExpr", "nullConstSubst")
    /** SQL Server: identifiers quoted, OFFSET without FETCH accepted, right-nested joins
      * parsed, CONCAT treats NULL as '' (Ermine's semantics). */
    val mssql: Set[String] = Set("keyword", "limitOffsetOnly", "nestedJoinRight", "concatNull")
  }

  val outerWidened = new java.util.concurrent.atomic.AtomicInteger(0)

  // ------------------------------------------------------------------ generators

  class Gens(val profile: Set[String]) {
    import Op._
    import Predicate._

    /** A class is produced when its flag is set, the audit closed it (`fixed`), OR
      * the backend does not exhibit it. */
    def on(cls: String): Boolean = SqlDifferential.active(cls) || profile(cls)

    def value(t: PrimT): Gen[PrimExpr] = genValue(t, decimal = on("decimalLiteral"), mixed = on("mixedCase"))

    /** A typed subtree: the header we believe it has, and the relation. */
    type Typed[R] = (Header, Relation[Nothing, R])

    def genLit[R](leaf: Option[Typed[R]]): Gen[Typed[R]] = leaf match {
      case Some(l) => Gen.frequency((3, Gen.const(l)), (7, genLiteral[R]))
      case None    => genLiteral[R]
    }

    /** 1-4 columns, 0-8 rows; a duplicate row is offered one time in four. */
    def genLiteral[R]: Gen[Typed[R]] = for {
      k    <- Gen.choose(1, 4)
      cs   <- Gen.pick(k, cols)
      n    <- Gen.frequency((1, Gen.const(0)), (6, Gen.choose(1, 8)))
      rows <- Gen.listOfN(n, genRow(cs.toList))
      dup  <- Gen.frequency((3, Gen.const(false)), (1, Gen.const(true)))
    } yield {
      val h: Header = cs.map(c => c.name -> c.t).toMap
      // O-2: a literal with duplicate rows scans with the duplicates on SQL Server
      val all = if (on("dupLit")) (if (dup && rows.nonEmpty) rows.head :: rows else rows)
                else Ref.dedupe(rows)
      all match {
        case Nil     => (h, RelEmpty(h))
        case r :: rs => (h, SmallLit(NonEmptyList.nel(r, scalaz.IList.fromList(rs))))
      }
    }

    def genRow(cs: List[Col]): Gen[Record] =
      Gen.sequence[List[(String, PrimExpr)], (String, PrimExpr)](
        cs.map(c => value(c.t).map(v => c.name -> v))).map(_.toMap)

    /** A literal with exactly the header `h` (for the right side of a union). */
    def genLiteralFor[R](h: Header): Gen[Typed[R]] = for {
      n    <- Gen.frequency((1, Gen.const(0)), (6, Gen.choose(1, 6)))
      rows <- Gen.listOfN(n, genRow(h.toList.map { case (c, t) => Col(c, t) }))
    } yield (if (on("dupLit")) rows else Ref.dedupe(rows)) match {
      case Nil     => (h, RelEmpty(h))
      case r :: rs => (h, SmallLit(NonEmptyList.nel(r, scalaz.IList.fromList(rs))))
    }

    // ---- expressions over a header

    /** An op of exactly `t`'s base type whose value can only be NULL if `t` is
      * nullable (so a header carrying `t` reads it back without "Unexpected NULL"). */
    def genOpOf(h: Header, t: PrimT, depth: Int): Gen[Op] = {
      val sameBase = h.toList.filter { case (_, ct) => ct isa t }   // ct.nullable <= t.nullable
      val colGen: Option[Gen[Op]] =
        if (sameBase.isEmpty) None
        else Some(Gen.oneOf(sameBase).map { case (c, ct) => ColumnValue(c, ct): Op })
      val litGen: Gen[Op] = value(t.withoutNull).map(OpLiteral(_): Op)
      val leafGen: Gen[Op] = colGen.map(cg => Gen.frequency((3, cg), (1, litGen))).getOrElse(litGen)
      if (depth <= 0) leafGen
      else {
        val deeper = Gen.frequency[Op](
          (3, leafGen),
          (if (isNumeric(t)) 2 else 0, for {
            // O-21: a double literal is DECIMAL on SQL Server and a product raises the
            // scale, which a UNION with a SUM then rounds away; without the class, doubles
            // are only added and subtracted
            f <- if (t.isInstanceOf[DoubleT] && !on("decimalLiteral")) Gen.oneOf[(Op, Op) => Op](Add(_, _), Sub(_, _))
                 else Gen.oneOf[(Op, Op) => Op](Add(_, _), Sub(_, _), Mul(_, _))
            a <- genOpOf(h, t, depth - 1); b <- genOpOf(h, t, depth - 1)
          } yield f(a, b)),
          (t match { case DoubleT(_) if on("decimalLiteral") => 1; case _ => 0 }, for {   // divisor: a non-zero literal
            a <- genOpOf(h, t, depth - 1); d <- Gen.oneOf(0.5, 1.5, -2.0, 3.0)
          } yield DoubleDiv(a, OpLiteral(DoubleExpr(false, d)))),
          (t match { case IntT(_) => 1; case _ => 0 }, for {
            a <- genOpOf(h, t, depth - 1); d <- Gen.oneOf(1, 2, 3, -2)
          } yield FloorDiv(a, OpLiteral(IntExpr(false, d)))),
          (2, for {
            p <- genPred(h, depth - 1); a <- genOpOf(h, t, depth - 1); b <- genOpOf(h, t, depth - 1); l <- leafGen
          } yield
            // O-16: an `if` whose CONSEQUENT is an `if` is merged into one CASE with
            // `not(test)` first, which is wrong when the test is UNKNOWN
            if (a.isInstanceOf[If] && !on("ifNestedConsequent")) If(p, l, b) else If(p, a, b)),
          (1, t match {
             case StringT(_, _) => for {
               k  <- Gen.choose(1, 3)
               xs <- Gen.listOfN(k, genOpOf(h, StringT(0, on("concatNull")), depth - 1))
             } yield Concat(xs)
             case _ => leafGen
           }),
          // O-23: string equality is case-insensitive in memory and in constant folding
          // (`PrimExprOrder` lower-cases), byte-wise on SQLite, collation-bound on SQL
          // Server; `upper`/`lower` make mixed case, so they join the `mixedCase` class
          (t match { case StringT(_, _) if on("mixedCase") => 1; case _ => 0 }, for {
            b <- Gen.oneOf[Builtin](Upper, Lower); a <- genOpOf(h, t, depth - 1)
          } yield BuiltinCall(b, List(a))),
          (1, {                                                     // coalesce(nullable column, literal)
            val nullables = h.toList.filter { case (_, ct) => ct.nullable && baseName(ct) == baseName(t) }
            if (nullables.isEmpty) leafGen
            else for {
              c <- Gen.oneOf(nullables); v <- value(t.withoutNull)
            } yield Coalesce(ColumnValue(c._1, c._2), OpLiteral(v))
          }))
        deeper
      }
    }

    /** Any op over `h`: pick a target type first. */
    def genOp(h: Header, depth: Int): Gen[(PrimT, Op)] = for {
      t  <- Gen.oneOf(h.values.toList.distinct)
      op <- genOpOf(h, t, depth)
    } yield (t, op)

    def genPred(h: Header, depth: Int): Gen[Predicate] = {
      val cmp: Gen[Predicate] = for {
        t <- Gen.oneOf(h.values.toList.distinct)
        f <- Gen.oneOf[(Op, Op) => Predicate](Lt(_, _), Gt(_, _), Eq(_, _))
        a <- genOpOf(h, t.withNull, 1)
        b <- genOpOf(h, t.withNull, 1)
      } yield
        // O-11: `Eq(x, x)` is simplified to TRUE, but over a NULL it is UNKNOWN in SQL;
        // the operands are compared AFTER `Op.simplify`, which is what the compiler folds
        if (a.simplify(Map()) == b.simplify(Map()) && !on("eqSelf")) Lt(a, b) else f(a, b)
      val isNull: Gen[Predicate] = for {
        c <- Gen.oneOf(h.toList)
      } yield IsNull(ColumnValue(c._1, c._2))
      val atom: Gen[Predicate] = Gen.oneOf(true, false).map(Atom(_))
      if (depth <= 0) Gen.frequency((6, cmp), (2, isNull), (1, atom))
      else Gen.frequency(
        (5, cmp), (2, isNull), (1, atom),
        (2, for { a <- genPred(h, depth - 1); b <- genPred(h, depth - 1) } yield And(a, b)),
        (2, for { a <- genPred(h, depth - 1); b <- genPred(h, depth - 1) } yield Or(a, b)),
        (2, genPred(h, depth - 1).map(Not(_))))
    }

    /** A name not in `h`. */
    def fresh(h: Header, taken: Set[String] = Set()): Gen[Option[String]] =
      freshNames.filterNot(n => h.contains(n) || taken(n)) match {
        case Nil => Gen.const(None)
        case xs  => Gen.oneOf(xs).map(Some(_))
      }

    // ---- the constructors

    def genRel[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] =
      if (depth <= 0) genLit(leaf)
      else Gen.frequency(
        (2, genLit(leaf)),
        (4, genFilter(depth, leaf)),
        (4, genProject(depth, leaf)),
        (4, genJoin(depth, leaf)),
        (2, genUnion(depth, leaf)),
        (2, genMinus(depth, leaf)),
        (2, genExcept(depth, leaf)),
        (2, genCombine(depth, leaf)),
        (2, genRename(depth, leaf)),
        (3, genLimit(depth, leaf)),
        (3, genAggBy(depth, leaf)),
        (2, genAgg(depth, leaf)),
        (if (leaf.isEmpty) 2 else 0, genLet(depth).map { case (h, r) => (h, r: Relation[Nothing, R]) }))   // one let level is enough

    def genFilter[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, r) <- genRel(depth - 1, leaf)
      // O-25: a column the Reflexivity knows to be the constant NULL is substituted into
      // the predicate as an untyped NULL literal, which SQL Server rejects inside CASE;
      // unless the class is enabled the predicate avoids such columns
      hp     =  if (on("nullConstSubst")) h else h -- nullConstCols(r)
      p      <- if (hp.isEmpty) Gen.const(None) else genPred(hp, 2).map(Some(_))
    } yield p match {
      case Some(pr) => (h, Filter(r, pr))
      case None     => (h, r)
    }

    /** Columns whose value the scanner's `Reflexivity` knows to be NULL (O-25): a
      * one-row literal's NULL cells, followed through the constructors that keep the
      * constancy. Over-approximated on purpose. */
    def nullConstCols[R](r: Relation[Nothing, R]): Set[String] = r match {
      case SmallLit(ts)      => ts.head.keySet.filter(c => ts.list.toList.forall(_(c).isNull))
      case Project(u, cs)    =>
        val under = nullConstCols(u)
        cs.collect { case (a, ColumnValue(c, _)) if under(c) => a.name }.toSet
      case Combine(u, _, _)  => nullConstCols(u)
      case Filter(u, _)      => nullConstCols(u)
      case Except(u, _)      => nullConstCols(u)
      case RenameR(u, a, to) => nullConstCols(u).map(c => if (c == a.name) to else c)
      case Limit(u, _, _, _) => nullConstCols(u)
      case Note(_, u)        => nullConstCols(u)
      case LetR(_, _, e)     => nullConstCols(e)
      case JoinOn(l, rr, _, _) => nullConstCols(l) ++ nullConstCols(rr)
      case Union(l, rr)      => nullConstCols(l) intersect nullConstCols(rr)
      case MinusI(l, _)      => nullConstCols(l)
      case AggregateByGroup(u, cs, _, _) =>
        val under = nullConstCols(u)
        cs.collect { case (a, ColumnValue(c, _)) if under(c) => a.name }.toSet
      case _                 => Set()
    }

    def genProject[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, r) <- genRel(depth - 1, leaf)
      keep0  <- Gen.someOf(h.toList)
      // O-9: a projection over an UNGROUPED aggregate that keeps none of its columns
      // loses the aggregate's one row; unless the class is enabled keep one column
      keep   =  if (keep0.isEmpty && !on("projectOverAggConst") && ungroupedAggBelow(r)) h.toList.take(1) else keep0
      nNew   <- Gen.choose(if (keep.isEmpty) 1 else 0, 2)
      news   <- genNewCols(h, nNew, Set())
    } yield {
      // O-14: a NON-INJECTIVE op over one column (coalesce, if, upper, floorDiv, x*0) is
      // taken as distinctness-preserving and the projection skips DISTINCT; unless the
      // class is enabled, such a projection also keeps every source column
      val keep2 = if (!on("projectNonInjective") && news.exists(n => nonInjective(n._3))) h.toList else keep
      val cs0: Map[Attribute, Op] =
        keep2.map { case (c, t) => Attribute(c, t) -> (ColumnValue(c, t): Op) }.toMap ++
        news.map { case (n, t, op) => Attribute(n, t) -> op }
      val cs = if (cs0.nonEmpty) cs0 else h.headOption.map { case (c, t) => Map(Attribute(c, t) -> (ColumnValue(c, t): Op)) }.getOrElse(cs0)
      (cs.map(_._1.tuple), Project(r, cs))
    }

    /** `n` new (name, type, op) columns over `h`, names distinct and outside `h`. */
    def genNewCols(h: Header, n: Int, taken: Set[String]): Gen[List[(String, PrimT, Op)]] =
      if (n <= 0) Gen.const(Nil)
      else fresh(h, taken).flatMap {
        case None => Gen.const(Nil)
        case Some(name) => for {
          (t, op) <- genOp(h, 2)
          rest    <- genNewCols(h, n - 1, taken + name)
        } yield {
          // the attribute type is what the op can produce; a nullable value under a
          // non-nullable attribute would be read back as "Unexpected NULL"
          val ty = op.guessType.fold(_ => t, identity)
          // O-24: a pure alias of a kept column duplicates its expression
          if (op.isInstanceOf[ColumnValue] && !on("orderDupExpr")) rest else (name, ty, op) :: rest
        }
      }

    def genCombine[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, r) <- genRel(depth - 1, leaf)
      news   <- genNewCols(h, 1, Set())
    } yield news match {
      case (n, t, op) :: _ => (h + (n -> t), Combine(r, Attribute(n, t), op))
      case Nil             => (h, r)
    }

    def genRename[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, r) <- genRel(depth - 1, leaf)
      from   <- Gen.oneOf(h.toList)
      to     <- fresh(h)
    } yield to match {
      case Some(n) => (h - from._1 + (n -> from._2), RenameR(r, Attribute(from._1, from._2), n))
      case None    => (h, r)
    }

    def genExcept[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, r) <- genRel(depth - 1, leaf)
      drop   <- Gen.someOf(h.keys.toList)
    } yield {
      val d = if (drop.size >= h.size) drop.toSet - h.keys.head else drop.toSet   // keep one column
      (h -- d, Except(r, d))
    }

    def genJoin[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (hl, l) <- genRel(depth - 1, leaf)
      (hr, r) <- genRel(depth - 1, leaf)
      pairs   <- {
        val lo = hl.toList.filterNot(c => hr.contains(c._1))
        val ro = hr.toList.filterNot(c => hl.contains(c._1))
        val cands = for { a <- lo; b <- ro; if a._2 == b._2 } yield (a._1, b._1)
        if (cands.isEmpty) Gen.const(Nil) else Gen.frequency((2, Gen.const(Nil)), (1, Gen.oneOf(cands).map(List(_))))
      }
      // O-1: inside a let body every outer join compiles as an inner join
      outer   =  if (leaf.isEmpty || on("letOuter")) 1 else 0
      mode0   <- Gen.frequency((4, Gen.const(JoinMode.Inner)), (outer, Gen.const(JoinMode.Left)),
                               (outer, Gen.const(JoinMode.Right)), (outer, Gen.const(JoinMode.Full)))
    } yield {
      val natural = hl.keySet intersect hr.keySet
      // an outer join answers NULL in the unmatched side's columns, which the header
      // must admit or the scan throws "Unexpected NULL" (pinned as O-3): the side that
      // can be unmatched is projected onto nullable column types, values unchanged
      def widen(h: Header, x0: Relation[Nothing, R], keep: Set[String]): (Header, Relation[Nothing, R]) = {
        // O-10: a computed column on the side that can be unmatched is inlined into the
        // join's select list and re-evaluated over NULLs; unless the class is enabled the
        // side is forced into a subquery through a union with itself
        val x = if (!on("outerJoinInlinedExpr") && computedTop(x0)) Union(x0, x0) else x0
        if (h.forall { case (c, t) => keep(c) || t.nullable }) (h, x)
        else {
          outerWidened.incrementAndGet()
          val nh = h.map { case (c, t) => c -> (if (keep(c)) t else t.withNull) }
          (nh, Project(x, h.map { case (c, t) => Attribute(c, nh(c)) -> (ColumnValue(c, t): Op) }))
        }
      }
      // O-28: a FULL JOIN over a nullable key coalesces a left-only and a right-only row
      // into equal rows and claims distinctness; unless the class is enabled such a
      // full join becomes a left join
      val mode1 = mode0 match {
        case JoinMode.Full if !on("fullJoinNullKey") && (natural.exists(c => hl(c).nullable) || pairs.exists { case (a, b) => hl(a).nullable || hr(b).nullable }) => JoinMode.Left
        case m => m
      }
      val ((hl2, l2), (hr2, r2)) = mode1 match {
        case JoinMode.Left  => ((hl, l), widen(hr, r, natural))
        case JoinMode.Right => (widen(hl, l, natural), (hr, r))
        case JoinMode.Full  => (widen(hl, l, natural), widen(hr, r, natural))
        case JoinMode.Inner => ((hl, l), (hr, r))
      }
      // the on-pairs must still agree in type after widening
      val pairs2 = pairs.filter { case (a, b) => hl2(a) == hr2(b) }
      // O-8: a join whose RIGHT operand compiles to a bare join source is emitted
      // right-nested without parentheses, which SQLite rejects; unless the class is
      // enabled, put the nesting side on the left (a symmetric rewrite) or, when both
      // nest, force the right into a subquery through a union with itself
      if (on("nestedJoinRight") || !rightNests(r2)) (hr2 ++ hl2, JoinOn(l2, r2, pairs2.toSet, mode1))
      else if (!rightNests(l2)) (hr2 ++ hl2, JoinOn(r2, l2, pairs2.map(_.swap).toSet, mode1.reverse))
      else (hr2 ++ hl2, JoinOn(l2, Union(r2, r2), pairs2.toSet, mode1))
    }

    /** Columns whose SQL type is the untyped NULL of an empty relation (O-22): SQL
      * Server infers it through derived tables, joins and limits; a union with a typed
      * arm types it. Over-approximated on purpose. */
    def nullTypedCols[R](r: Relation[Nothing, R]): Set[String] = r match {
      case RelEmpty(h)       => h.keySet
      case SmallLit(ts)      => ts.head.keySet.filter(c => ts.list.toList.forall(_(c).isNull))   // an all-NULL TVC column is untyped too
      case Project(u, cs)    =>
        val under = nullTypedCols(u)
        cs.collect { case (a, ColumnValue(c, _)) if under(c) => a.name }.toSet
      case Combine(u, _, _)  => nullTypedCols(u)
      case Filter(u, _)      => nullTypedCols(u)
      case Except(u, _)      => nullTypedCols(u)
      case RenameR(u, a, to) => nullTypedCols(u).map(c => if (c == a.name) to else c)
      case Limit(u, _, _, _) => nullTypedCols(u)
      case Note(_, u)        => nullTypedCols(u)
      case LetR(_, _, e)     => nullTypedCols(e)
      case JoinOn(l, rr, _, _) => nullTypedCols(l) ++ nullTypedCols(rr)
      case Union(l, rr)      => nullTypedCols(l) intersect nullTypedCols(rr)
      case MinusI(l, _)      => nullTypedCols(l)
      case AggregateByGroup(u, cs, _, _) =>
        val under = nullTypedCols(u)
        cs.collect { case (a, ColumnValue(c, _)) if under(c) => a.name }.toSet
      case _                 => Set()
    }

    /** Columns that reach the top `select` as CONSTANT expressions (O-15): literal
      * projections, and every column of a one-row literal under an inner join (the
      * scanner squashes it into the other side's select). */
    def constCols[R](r: Relation[Nothing, R]): Set[String] = r match {
      case Project(u, cs)    =>
        val under = constCols(u)
        cs.collect { case (a, OpLiteral(_)) => a.name; case (a, ColumnValue(c, _)) if under(c) => a.name }.toSet
      case Combine(u, a, op) => constCols(u) ++ (op match { case OpLiteral(_) => Set(a.name); case _ => Set[String]() })
      case Filter(u, _)      => constCols(u)
      case Except(u, _)      => constCols(u)
      case RenameR(u, a, to) => constCols(u).map(c => if (c == a.name) to else c)
      case Note(_, u)        => constCols(u)
      case LetR(_, _, e)     => constCols(e)
      case JoinOn(l, rr, _, JoinMode.Inner) => single(l) ++ single(rr) ++ constCols(l) ++ constCols(rr)
      case _                 => Set()
    }
    private def single[R](r: Relation[Nothing, R]): Set[String] = r match {
      case SmallLit(ts) if ts.tail.isEmpty => ts.head.keySet
      case _ => Set()
    }

    /** An op the scanner's `preservesDistinctness` takes for injective and is not (O-14). */
    def nonInjective(op: Op): Boolean = op match {
      case Coalesce(_, _) | If(_, _, _) | BuiltinCall(_, _) | FloorDiv(_, _) | Mul(_, _) => true
      case Add(a, b)       => nonInjective(a) || nonInjective(b)
      case Sub(a, b)       => nonInjective(a) || nonInjective(b)
      case DoubleDiv(a, b) => nonInjective(a) || nonInjective(b)
      case Concat(xs)      => xs.exists(nonInjective)
      case _               => false
    }

    /** Does `r`'s top `select` carry an expression that is not a plain column (finding O-10)? */
    def computedTop[R](r: Relation[Nothing, R]): Boolean = r match {
      case Project(u, cs)    => cs.exists { case (_, op) => !op.isInstanceOf[ColumnValue] } || computedTop(u)
      case Combine(_, _, _)  => true
      case Filter(u, _)      => computedTop(u)
      case Except(u, _)      => computedTop(u)
      case RenameR(u, _, _)  => computedTop(u)
      case Note(_, u)        => computedTop(u)
      case LetR(_, _, e)     => computedTop(e)
      case JoinOn(l, rr, _, _) => computedTop(l) || computedTop(rr)   // a join's select merges both sides' attrs
      case _                 => false
    }

    /** Is `r` an aggregate with no GROUP BY, seen through the constructors that keep its
      * `select` (finding O-9)? */
    def ungroupedAggBelow[R](r: Relation[Nothing, R]): Boolean = r match {
      case _: Aggregate[_, _]              => true
      case AggregateByGroup(_, _, _, grp)  => grp.isEmpty
      case Filter(u, _)      => ungroupedAggBelow(u)
      case Project(u, _)     => ungroupedAggBelow(u)
      case Combine(u, _, _)  => ungroupedAggBelow(u)
      case Except(u, _)      => ungroupedAggBelow(u)
      case RenameR(u, _, _)  => ungroupedAggBelow(u)
      case Note(_, u)        => ungroupedAggBelow(u)
      case LetR(_, _, e)     => ungroupedAggBelow(e)
      case _                 => false
    }

    /** Does `r` compile to a `select` whose source is a join (nothing between the join
      * and the root forces a subquery)? */
    def rightNests[R](r: Relation[Nothing, R]): Boolean = r match {
      case _: JoinOn[_, _]   => true
      case Filter(u, _)      => rightNests(u)
      case Project(u, _)     => rightNests(u)
      case Combine(u, _, _)  => rightNests(u)
      case Except(u, _)      => rightNests(u)
      case RenameR(u, _, _)  => rightNests(u)
      case Note(_, u)        => rightNests(u)
      case LetR(_, _, e)     => rightNests(e)
      case _                 => false
    }

    def genUnion[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, l) <- genRel(depth - 1, leaf)
      r      <- genSameHeader(h, depth - 1, leaf)
    } yield (h, Union(l, r))

    def genMinus[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, l) <- genRel(depth - 1, leaf)
      r      <- genSameHeader(h, depth - 1, leaf)
    } yield (h, MinusI(l, r))

    /** A relation with EXACTLY header `h`: a literal, or a projection of a subtree. */
    def genSameHeader[R](h: Header, depth: Int, leaf: Option[Typed[R]]): Gen[Relation[Nothing, R]] =
      Gen.frequency(
        (2, genLiteralFor[R](h).map(_._2)),
        (2, for {
          (sh, s0) <- genRel(depth, leaf)
          s        =  if (!on("projectOverAggConst") && ungroupedAggBelow(s0)) Union(s0, s0) else s0   // O-9
          cs0      <- Gen.sequence[List[(Attribute, Op)], (Attribute, Op)](h.toList.map { case (c, t) =>
                        genOpOf(sh, t, if (on("projectNonInjective")) 1 else 0).map(op => Attribute(c, t) -> op) })   // O-14: leaves only
          lits     <- Gen.sequence[List[PrimExpr], PrimExpr](h.toList.map { case (_, t) => value(t.withoutNull) })
        } yield {
          // O-24: two target columns aliasing one source column order by it twice
          val cs = if (on("orderDupExpr")) cs0 else {
            val seen = scala.collection.mutable.Set[Op]()
            cs0.zip(lits).map { case ((a, op), l) =>
              if (op.isInstanceOf[ColumnValue] && !seen.add(op)) a -> (OpLiteral(l): Op) else a -> op
            }
          }
          Project(s, cs.toMap)
        }))

    def genLimit[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, r) <- genRel(depth - 1, leaf)
      dirs   <- Gen.listOfN(h.size, Gen.oneOf(Asc, Desc))
      start  <- Gen.frequency((1, Gen.const(None)), (2, Gen.choose(1, 3).map(Some(_))))
      end    <- Gen.frequency((if (on("limitOffsetOnly")) 1 else 0, Gen.const(None)), (3, Gen.choose(1, 6).map(Some(_))))
    } yield {
      val order = h.keys.toList.sorted.zip(dirs)   // a total order: every column
      val (s, e) = (start, end) match {
        case (Some(a), Some(b)) if a > b => (Some(b), Some(a))
        case x => x
      }
      // O-13: a two-row range (to - from == 1) is taken for one row and the projection
      // above skips DISTINCT; unless the class is enabled, make it three rows
      val e2 = (s, e) match {
        case (Some(a), Some(b)) if b - a == 1 && !on("limitTwoRowsDistinct") => Some(a + 2)
        case (None, Some(2)) if !on("limitTwoRowsDistinct") => Some(3)
        // O-26: `from == to > 1` takes the one-row shortcut and skips DISTINCT on the
        // input, so it delivers row #from of the NON-deduplicated stream
        case (Some(a), Some(b)) if a == b && a > 1 && !on("limitOneRowOffset") => Some(a + 2)
        case _ => e
      }
      // O-27: an ORDER BY expression over constant columns (an empty relation's, a
      // one-row literal's) is rejected by SQL Server as constant; unless the class is
      // enabled a child with computed columns over constants is forced into a union
      val r2 = if (!on("orderByConstExpr") && computedTop(r) && (constCols(r) ++ nullTypedCols(r) ++ nullConstCols(r)).nonEmpty) Union(r, r) else r
      (h, Limit(r2, s, e2, order))
    }

    private def genAggFunc(h: Header, nullTyped: Set[String] = Set()): Gen[(PrimT, AggFunc)] = {
      // O-22: a column whose SQL type is the untyped NULL of `emitEmpty` is rejected by
      // SQL Server under MIN/MAX/SUM/AVG; unless the class is enabled skip those columns
      val usable = if (on("emptyAgg")) h.toList else h.toList.filterNot(c => nullTyped(c._1))
      val nums = usable.filter(c => isNumeric(c._2))
      // O-21: AVG over DECIMAL (a double literal on SQL Server) has six decimal places
      val avgs = if (on("decimalLiteral")) nums else nums.filter(c => c._2 match { case IntT(_) => true; case _ => false })
      val ords = usable.filter(c => c._2 match { case BooleanT(_) => false; case _ => true })
      // `Gen.oneOf` throws on an empty collection even under a zero weight, so the
      // table holds only the applicable entries
      val entries: List[(Int, Gen[(PrimT, AggFunc)])] =
        List((2, Gen.const((IntT(false), AggFunc.Count: AggFunc)))) ++
        (if (nums.isEmpty) Nil else List(
          (3, Gen.oneOf(nums).map { case (c, t) => (t.withNull, AggFunc.Sum(ColumnValue(c, t)): AggFunc) }))) ++
        (if (avgs.isEmpty) Nil else List(
          (2, Gen.oneOf(avgs).map { case (c, t) => (t.withNull, AggFunc.Avg(ColumnValue(c, t)): AggFunc) }))) ++
        (if (ords.isEmpty) Nil else List(
          (2, Gen.oneOf(ords).map { case (c, t) => (t.withNull, AggFunc.Min(ColumnValue(c, t)): AggFunc) }),
          (2, Gen.oneOf(ords).map { case (c, t) => (t.withNull, AggFunc.Max(ColumnValue(c, t)): AggFunc) })))
      Gen.frequency(entries: _*)
    }

    def genAggBy[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, r) <- genRel(depth - 1, leaf)
      ng     <- Gen.choose(0, math.min(2, h.size))
      grp0   <- Gen.pick(ng, h.toList)
      // O-15: a GROUP BY whose expressions are all constants at the select level is
      // dropped by the emitter, turning "no groups" into one row; unless the class is
      // enabled such a grouping becomes an ungrouped aggregate
      grp    =  if (!on("groupByConst") && grp0.nonEmpty && grp0.forall(c => constCols(r)(c._1))) Nil else grp0.toList
      na0    <- Gen.choose(1, 2)
      na     =  math.min(na0, freshNames.count(n => !h.contains(n)))
      aggs0  <- Gen.listOfN(na, genAggFunc(h, nullTypedCols(r)))
      names  <- Gen.pick(na, freshNames.filterNot(h.contains))
    } yield if (na == 0) (h, r) else {
      // O-24: two columns with the same expression are ordered by that expression twice
      val aggs = if (on("orderDupExpr")) aggs0 else aggs0.distinct
      val group = grp.toList.map { case (c, t) => ColumnValue(c, t) }
      val cs: Map[Attribute, Op] = grp.toList.map { case (c, t) => Attribute(c, t) -> (ColumnValue(c, t): Op) }.toMap
      val as = names.toList.zip(aggs).map { case (n, (t, f)) => (Attribute(n, t), f) }
      val nh: Header = cs.map(_._1.tuple) ++ as.map(_._1.tuple)
      (nh, AggregateByGroup(r, cs, as, group))
    }

    def genAgg[R](depth: Int, leaf: Option[Typed[R]]): Gen[Typed[R]] = for {
      (h, r) <- genRel(depth - 1, leaf)
      (t, f) <- genAggFunc(h, nullTypedCols(r))
      n      <- Gen.oneOf(freshNames)
    } yield (Map(n -> t), Aggregate(r, Attribute(n, t), f))

    /** `LetR(ExtRel(bound), Nil, body)` where the body uses `VarR(RTop)` as a leaf. */
    def genLet(depth: Int): Gen[Typed[Nothing]] = for {
      (bh, b)   <- genRel[Nothing](depth - 1, None)
      (eh, e)   <- genRel[RLevel[Nothing, Nothing]](depth - 1, Some((bh, VarR(RTop))))
    } yield (eh, LetR(ExtRel(b, ""), Nil, e))

    def genTop: Gen[Rel] = for {
      d      <- Gen.choose(1, 4)
      (_, r) <- genRel[Nothing](d, None)
    } yield r
  }

  // ------------------------------------------------------------------ shrinking

  /** The direct relational children (each a closed, well-typed relation on its own),
    * and for a let, the body with the bound relation inlined. */
  def children[R](r: Relation[Nothing, R]): Stream[Relation[Nothing, R]] = r match {
    case Filter(u, _)               => Stream(u)
    case Project(u, _)              => Stream(u)
    case Combine(u, _, _)           => Stream(u)
    case Except(u, _)               => Stream(u)
    case RenameR(u, _, _)           => Stream(u)
    case Limit(u, _, _, _)          => Stream(u)
    case AggregateByGroup(u, _, _, _) => Stream(u)
    case Aggregate(u, _, _)         => Stream(u)
    case JoinOn(l, rr, _, _)        => Stream(l, rr)
    case Union(l, rr)               => Stream(l, rr)
    case MinusI(l, rr)              => Stream(l, rr)
    case Note(_, u)                 => Stream(u)
    case LetR(ExtRel(b, _), _, e)   => Stream(b) ++ Stream(inlineLet(b, e))
    case _                          => Stream.empty
  }

  /** `Relation.instantiate` without `flatMap`, which loses `JoinOn.mode` (finding O-1). */
  def inlineLet[R](b: Relation[Nothing, R], e: Relation[Nothing, RLevel[Nothing, R]]): Relation[Nothing, R] = {
    def go(x: Relation[Nothing, RLevel[Nothing, R]]): Relation[Nothing, R] = x match {
      case VarR(RTop)                 => b
      case VarR(RPop(v))              => v
      case Filter(u, p)               => Filter(go(u), p)
      case Project(u, cs)             => Project(go(u), cs)
      case Combine(u, a, op)          => Combine(go(u), a, op)
      case Except(u, cs)              => Except(go(u), cs)
      case RenameR(u, a, c)           => RenameR(go(u), a, c)
      case Limit(u, s, t, o)          => Limit(go(u), s, t, o)
      case AggregateByGroup(u, cs, as, g) => AggregateByGroup(go(u), cs, as, g)
      case Aggregate(u, a, f)         => Aggregate(go(u), a, f)
      case JoinOn(l, rr, cs, m)       => JoinOn(go(l), go(rr), cs, m)
      case Union(l, rr)               => Union(go(l), go(rr))
      case MinusI(l, rr)              => MinusI(go(l), go(rr))
      case Note(t, u)                 => Note(t, go(u))
      case h: HardRel                 => h
      case other                      => sys.error("inline: unsupported " + other.getClass.getSimpleName)
    }
    go(e)
  }

  /** Every relation obtained by dropping ONE row of ONE literal somewhere in `r`
    * (a one-row literal becomes `RelEmpty`), plus a filter with a sub-predicate. */
  def smaller[R](r: Relation[Nothing, R]): Stream[Relation[Nothing, R]] = r match {
    case SmallLit(ts) =>
      val rows = ts.list.toList
      val h = recordHeader(rows.head)
      rows.indices.toStream.map { i =>
        val kept = rows.take(i) ++ rows.drop(i + 1)
        kept match {
          case Nil     => RelEmpty(h)
          case x :: xs => SmallLit(NonEmptyList.nel(x, scalaz.IList.fromList(xs)))
        }
      }
    case Filter(u, p)               => subPreds(p).map(Filter(u, _)) ++ smaller(u).map(Filter(_, p))
    case Project(u, cs)             => smaller(u).map(Project(_, cs))
    case Combine(u, a, op)          => smaller(u).map(Combine(_, a, op))
    case Except(u, cs)              => smaller(u).map(Except(_, cs))
    case RenameR(u, a, c)           => smaller(u).map(RenameR(_, a, c))
    case Limit(u, s, t, o)          => smaller(u).map(Limit(_, s, t, o))
    case AggregateByGroup(u, cs, as, g) => smaller(u).map(AggregateByGroup(_, cs, as, g))
    case Aggregate(u, a, f)         => smaller(u).map(Aggregate(_, a, f))
    case JoinOn(l, rr, cs, m)       => smaller(l).map(JoinOn(_, rr, cs, m)) ++ smaller(rr).map(JoinOn(l, _, cs, m))
    case Union(l, rr)               => smaller(l).map(Union(_, rr)) ++ smaller(rr).map(Union(l, _))
    case MinusI(l, rr)              => smaller(l).map(MinusI(_, rr)) ++ smaller(rr).map(MinusI(l, _))
    case Note(t, u)                 => smaller(u).map(Note(t, _))
    case LetR(ExtRel(b, db), pk, e) => smaller(b).map(b2 => LetR(ExtRel(b2, db), pk, e)) ++
                                       smaller(e).map(e2 => LetR(ExtRel(b, db), pk, e2))
    case _                          => Stream.empty
  }

  private def subPreds(p: Predicate): Stream[Predicate] = p match {
    case Predicate.And(a, b) => Stream(a, b)
    case Predicate.Or(a, b)  => Stream(a, b)
    case Predicate.Not(a)    => Stream(a)
    case _                   => Stream.empty
  }

  implicit val shrinkRel: Shrink[Rel] = Shrink { r => children(r) ++ smaller(r) }

  // ------------------------------------------------------------------ normal forms

  /** A cell normalised for comparison: doubles to 9 significant digits, dates to
    * epoch days, every NULL alike (a `NullExpr` is never `==` to anything). */
  sealed abstract class Norm
  case object NNull extends Norm
  final case class NInt(v: Long) extends Norm
  final case class NDbl(v: BigDecimal) extends Norm
  final case class NStr(v: String) extends Norm
  final case class NBool(v: Boolean) extends Norm
  final case class NDate(epochDay: Long) extends Norm

  def norm(e: PrimExpr): Norm = e match {
    case NullExpr(_)         => NNull
    case IntExpr(_, v)       => NInt(v)
    case LongExpr(_, v)      => NInt(v)
    case ShortExpr(_, v)     => NInt(v)
    case ByteExpr(_, v)      => NInt(v)
    case DoubleExpr(_, v)    => NDbl(if (v == 0.0) BigDecimal(0) else BigDecimal(v).round(new java.math.MathContext(9)))
    case StringExpr(_, v)    => NStr(v)
    case BooleanExpr(_, v)   => NBool(v)
    case DateExpr(_, d)      => NDate(Math.floorDiv(d.getTime, 86400000L))
    case TimestampExpr(_, t) => NDate(Math.floorDiv(t.getTime, 86400000L))
    case UuidExpr(_, u)      => NStr(u.toString)
  }

  type Key = Map[String, Norm]
  def key(r: Record): Key = r.map { case (c, v) => c -> norm(v) }
  def multiset(rs: Seq[Record]): Map[Key, Int] = rs.groupBy(key).map { case (k, v) => k -> v.size }

  def showRows(rs: Seq[Record]): String =
    if (rs.isEmpty) "  (no rows)"
    else rs.map(r => "  " + r.toList.sortBy(_._1).map { case (c, v) => c + "=" + (if (v.isNull) "NULL" else v.toString) }.mkString(", ")).sorted.mkString("\n")

  // ------------------------------------------------------------------ the reference

  object Ref {
    import Op._
    import Predicate._

    sealed abstract class TV
    case object T extends TV; case object F extends TV; case object U extends TV

    def not(a: TV): TV = a match { case T => F; case F => T; case U => U }
    def and(a: TV, b: TV): TV = (a, b) match { case (F, _) | (_, F) => F; case (T, T) => T; case _ => U }
    def or(a: TV, b: TV): TV = (a, b) match { case (T, _) | (_, T) => T; case (F, F) => F; case _ => U }

    /** `-1`, `0`, `1` on two non-null cells of the same base type. */
    def compare(a: PrimExpr, b: PrimExpr): Int = (norm(a), norm(b)) match {
      case (NInt(x), NInt(y))   => java.lang.Long.compare(x, y)
      case (NDbl(x), NDbl(y))   => x compare y
      case (NInt(x), NDbl(y))   => BigDecimal(x) compare y
      case (NDbl(x), NInt(y))   => x compare BigDecimal(y)
      case (NStr(x), NStr(y))   => x compareTo y
      case (NBool(x), NBool(y)) => java.lang.Boolean.compare(x, y)
      case (NDate(x), NDate(y)) => java.lang.Long.compare(x, y)
      case (x, y)               => sys.error("reference: cannot compare " + x + " with " + y)
    }

    def pred(p: Predicate, r: Record): TV = p match {
      case Atom(b)      => if (b) T else F
      case Lt(a, b)     => cmp(a, b, r)(_ < 0)
      case Gt(a, b)     => cmp(a, b, r)(_ > 0)
      case Eq(a, b)     => cmp(a, b, r)(_ == 0)
      case Not(q)       => not(pred(q, r))
      case And(a, b)    => and(pred(a, r), pred(b, r))
      case Or(a, b)     => or(pred(a, r), pred(b, r))
      case IsNull(e)    => if (op(e, r).isNull) T else F
      case Funtest(n, _, _, _) => sys.error("reference: no funtest " + n)
    }

    private def cmp(a: Op, b: Op, r: Record)(f: Int => Boolean): TV = {
      val (x, y) = (op(a, r), op(b, r))
      if (x.isNull || y.isNull) U else if (f(compare(x, y))) T else F
    }

    /** SQL NULL propagation first, then `Op.eval` on the node with its children
      * replaced by literals. */
    def op(o: Op, r: Record): PrimExpr = o match {
      case OpLiteral(l)       => l
      case ColumnValue(c, _)  => r.getOrElse(c, sys.error("reference: no column " + c + " in " + r.keySet))
      case If(t, c, a)        => if (pred(t, r) == T) op(c, r) else op(a, r)
      case Coalesce(a, b)     => val x = op(a, r); if (x.isNull) op(b, r) else x
      case Concat(xs)         => Concat(xs.map(x => OpLiteral(op(x, r)))).eval(Map())   // Ermine: NULL is ""
      case Add(a, b)          => bin(Add(_, _), a, b, r)
      case Sub(a, b)          => bin(Sub(_, _), a, b, r)
      case Mul(a, b)          => bin(Mul(_, _), a, b, r)
      case FloorDiv(a, b)     => bin(FloorDiv(_, _), a, b, r)
      case DoubleDiv(a, b)    => bin(DoubleDiv(_, _), a, b, r)
      case BuiltinCall(f, as) =>
        val vs = as.map(op(_, r))
        vs.find(_.isNull).getOrElse(BuiltinCall(f, vs.map(OpLiteral(_))).eval(Map()))
      case other              => sys.error("reference: unsupported op " + other)
    }

    private def bin(f: (Op, Op) => Op, a: Op, b: Op, r: Record): PrimExpr = {
      val (x, y) = (op(a, r), op(b, r))
      if (x.isNull) x else if (y.isNull) y else f(OpLiteral(x), OpLiteral(y)).eval(Map())
    }

    def dedupe(rs: Rows): Rows = {
      val seen = scala.collection.mutable.HashSet[Key]()
      rs.filter(r => seen.add(key(r)))
    }

    /** SQL ORDER BY: NULLs first ascending (SQLite and SQL Server alike). */
    def sortBy(rs: Rows, order: List[(String, SortOrder)]): Rows = {
      val ord = new Ordering[Record] {
        def compare(a: Record, b: Record): Int = {
          var i = order
          while (i.nonEmpty) {
            val (c, dir) = i.head
            val (x, y) = (a(c), b(c))
            val k =
              if (x.isNull && y.isNull) 0
              else if (x.isNull) -1
              else if (y.isNull) 1
              else Ref.compare(x, y)
            val d = dir match { case Asc => k; case Desc => -k }
            if (d != 0) return d
            i = i.tail
          }
          0
        }
      }
      rs.sorted(ord)
    }

    def agg(f: AggFunc, t: PrimT, rs: Rows): PrimExpr = f match {
      case AggFunc.Count => IntExpr(false, rs.size)
      case AggFunc.Sum(o) =>
        val vs = rs.map(op(o, _)).filterNot(_.isNull)
        if (vs.isEmpty) NullExpr(t) else vs.reduceLeft(_ + _)
      case AggFunc.Avg(o) =>
        val vs = rs.map(op(o, _)).filterNot(_.isNull)
        if (vs.isEmpty) NullExpr(t)
        else vs.head match {
          case _: DoubleExpr => DoubleExpr(true, vs.map(_.extractDouble).sum / vs.size)
          case _             => IntExpr(true, (vs.map(_.extractLong).sum / vs.size).toInt)   // integer AVG truncates
        }
      case AggFunc.Min(o) =>
        val vs = rs.map(op(o, _)).filterNot(_.isNull)
        if (vs.isEmpty) NullExpr(t) else vs.reduceLeft((a, b) => if (compare(a, b) <= 0) a else b)
      case AggFunc.Max(o) =>
        val vs = rs.map(op(o, _)).filterNot(_.isNull)
        if (vs.isEmpty) NullExpr(t) else vs.reduceLeft((a, b) => if (compare(a, b) >= 0) a else b)
      case other => sys.error("reference: unsupported aggregate " + other)
    }

    def eval[R](rel: Relation[Nothing, R], leaf: R => Rows, lh: R => Header): Rows = {
      def go(x: Relation[Nothing, R]): Rows = eval(x, leaf, lh)
      rel match {
        case VarR(v)            => leaf(v)
        case SmallLit(ts)       => dedupe(ts.list.toList)
        case RelEmpty(_)        => Nil
        case Filter(u, p)       => go(u).filter(r => pred(p, r) == T)
        case Project(u, cs)     => dedupe(go(u).map(r => cs.map { case (a, o) => a.name -> op(o, r) }))
        case Combine(u, a, o)   => go(u).map(r => r + (a.name -> op(o, r)))
        case Except(u, cs)      => dedupe(go(u).map(_ -- cs))
        case RenameR(u, a, to)  => go(u).map(r => r - a.name + (to -> r(a.name)))
        case Union(l, r)        => dedupe(go(l) ++ go(r))
        case MinusI(l, r)       => val ks = go(r).map(key).toSet; go(l).filterNot(x => ks(key(x)))
        case Limit(u, s, e, o)  =>
          val sorted = sortBy(go(u), o)
          val from = s.getOrElse(1)
          val upto = e.getOrElse(Int.MaxValue)
          if (upto < from) Nil else sorted.drop(from - 1).take(upto - from + 1)
        case JoinOn(l, r, cs, mode) =>
          val (ls, rs) = (go(l), go(r))
          val hl = headerOf(l, lh); val hr = headerOf(r, lh)
          val natural = (hl.keySet intersect hr.keySet).toList
          val pairs = natural.map(c => (c, c)) ++ cs.toList
          def matches(a: Record, b: Record) = pairs.forall { case (x, y) =>
            val (p, q) = (a(x), b(y)); !p.isNull && !q.isNull && compare(p, q) == 0 }
          def nulls(h: Header, keep: Set[String]) = h.collect { case (c, t) if !keep(c) => c -> NullExpr(t) }
          val inner = for { a <- ls; b <- rs; if matches(a, b) } yield (mode match {
            case JoinMode.Right => a ++ b          // right's key columns win
            case _              => b ++ a          // left's key columns win (inner, left, full)
          })
          val leftOnly = if (mode == JoinMode.Left || mode == JoinMode.Full)
            ls.filterNot(a => rs.exists(matches(a, _))).map(a => nulls(hr, hl.keySet) ++ a) else Nil
          val rightOnly = if (mode == JoinMode.Right || mode == JoinMode.Full)
            rs.filterNot(b => ls.exists(matches(_, b))).map(b => nulls(hl, hr.keySet) ++ b) else Nil
          dedupe(inner ++ leftOnly ++ rightOnly)
        case AggregateByGroup(u, cs, as, group) =>
          val rs = go(u)
          val gcols = group.map(_.col)
          val groups: List[Rows] =
            if (gcols.isEmpty) List(rs)
            else rs.groupBy(r => gcols.map(c => norm(r(c)))).values.toList
          groups.map { g =>
            // `cs` is over the group columns only, so an empty group (no GROUP BY, no rows) has none
            val csVals: Record = if (g.isEmpty) Map() else cs.map { case (a, o) => a.name -> op(o, g.head) }
            csVals ++ as.map { case (a, f) => a.name -> agg(f, a.t, g) }
          }
        case Aggregate(u, a, f) =>
          // Decision D2 (scanner C6, prims P4): over NO rows an ungrouped SUM answers
          // its typed zero, COUNT 0, and AVG/MIN/MAX answer no row at all.  The SQL is
          // `coalesce(SUM(x), 0)`, so an ungrouped SUM whose inputs are ALL NULL is 0 too
          // (review-scanner NOTE 1; the in-memory `sumMonoid` skips NULLs and agrees).
          // A GROUPED SUM is plain `SUM(x)`: NULL over an all-NULL group, as `agg` says.
          val rs = go(u)
          val zero = PrimExpr.sumMonoid(a.t).zero
          if (rs.nonEmpty) {
            val v = agg(f, a.t, rs)
            List(Map(a.name -> (f match { case AggFunc.Sum(_) if v.isNull => zero; case _ => v })))
          } else f match {
            case AggFunc.Count  => List(Map(a.name -> IntExpr(false, 0)))
            case AggFunc.Sum(_) => List(Map(a.name -> zero))
            case _              => Nil
          }
        case LetR(ExtRel(b, _), _, e) =>
          val bound = go(b)
          eval[RLevel[Nothing, R]](e, { case RTop => bound; case RPop(v) => go(v) },
                                      { case RTop => headerOf(b, lh); case RPop(v) => headerOf(v, lh) })
        case Note(_, u)         => go(u)
        case other              => sys.error("reference: unsupported relation " + other.getClass.getSimpleName)
      }
    }

    /** The header of `r` as `Typer` sees it (for the NULL padding of outer joins). */
    def headerOf[R](r: Relation[Nothing, R], lh: R => Header): Header = {
      import scalaz.std.either._
      Typer.relTyperAux[Typer.TT, Nothing, R](r, (v: R) => Right(lh(v)): Typer.TT[Header], (x: Nothing) => x)
        .fold(e => sys.error(e.toString), h => h)
    }

    private implicit val ttErrs: Typer.Errs[Typer.TT] = new Typer.Errs[Typer.TT] {
      def apply(x: String, xs: String*): Either[NonEmptyList[String], Nothing] =
        Left(NonEmptyList.nel(x, scalaz.IList.fromList(xs.toList)))
    }
  }

  // ------------------------------------------------------------------ the backends

  final case class Scan(rows: Either[String, Vector[Record]], sql: String)

  /** sbt runs a suite's properties concurrently and a JDBC connection is not thread-safe
    * for concurrent statements: one scan at a time on the shared connection. */
  val scanLock = new Object

  def scan(scanner: SqlScanner, conn: Connection, rel: Rel): Scan = scanLock.synchronized {
    val sql = try scanner.dumpRel(rel) catch { case e: Throwable => "<dumpRel threw " + e + ">" }
    val rows = try Right(scanner.scanRel[Vector[Record]](rel, Process((r: Record) => Vector(r)))(vectorMonoid[Record]).apply(conn))
               catch { case e: Throwable => Left(e.getClass.getName + ": " + String.valueOf(e.getMessage).take(600)) }
    Scan(rows, sql)
  }

  /** The comparison, as a labelled `Prop`. */
  def compare(name: String, rel: Rel, header: Header, ref: Rows, s: Scan): Prop = {
    val show = "relation: " + rel + "\n" + name + " SQL:\n" + s.sql + "\nreference rows:\n" + showRows(ref)
    s.rows match {
      case Left(err) => Prop.falsified :| (name + " threw " + err + "\n" + show)
      case Right(rows) =>
        val dup = multiset(rows).filter(_._2 > 1)
        val a = multiset(ref).keySet; val b = multiset(rows).keySet
        val cols = rows.headOption.map(_.keySet).getOrElse(header.keySet)
        (Prop(!s.sql.contains("TODO")) :| (name + ": TODO in the emitted SQL\n" + show)) &&
        ((cols ?= header.keySet) :| (name + ": columns differ from the header\n" + show)) &&
        (Prop(dup.isEmpty) :| (name + ": DUPLICATE rows (a relation is a set): " + dup.keys.mkString("; ") + "\n" + show)) &&
        (Prop(a == b) :| (name + " rows differ\n" + show + "\n" + name + " rows:\n" + showRows(rows) +
                          "\nonly in reference:\n" + showRows(ref.filterNot(r => b(key(r)))) +
                          "\nonly in " + name + ":\n" + showRows(rows.filterNot(r => a(key(r))))))
    }
  }

  // ------------------------------------------------------------------ bookkeeping

  val generated  = new java.util.concurrent.atomic.AtomicInteger(0)
  val discarded  = new java.util.concurrent.atomic.AtomicInteger(0)
  val ctorCounts = scala.collection.mutable.Map[String, Int]()

  def count(r: Rel): Unit = {
    def go[R](x: Relation[Nothing, R]): Unit = {
      val k = x match { case j: JoinOn[_, _] => "JoinOn." + j.mode; case _ => x.getClass.getSimpleName }
      ctorCounts.synchronized { ctorCounts(k) = ctorCounts.getOrElse(k, 0) + 1 }
      x match {
        case LetR(ExtRel(b, _), _, e) => go(b); go(e)
        case _ => children(x).foreach(go)
      }
    }
    go(r)
  }

  def coverageLine: String =
    "[sqldiff] generated " + generated.get + ", discarded (ill-typed) " + discarded.get +
      ", outer-join sides widened to nullable " + outerWidened.get + "; discard reasons: " +
      discardReasons.synchronized { discardReasons.toList.sortBy(-_._2).take(3).map { case (k, v) => v + "x " + k }.mkString(" | ") } +
      "; constructors: " +
      ctorCounts.synchronized { ctorCounts.toList.sortBy(-_._2).map { case (k, v) => k + "=" + v }.mkString(" ") }

  /** The generator measured on its own (sbt runs properties in no fixed order, so
    * the random property's counters cannot be read "at the end"): `n` candidates
    * drawn, typed and counted, no scan. */
  def coverage(gens: Gens, n: Int): Prop = {
    val params = Gen.Parameters.default
    var seed = org.scalacheck.rng.Seed.random()
    (1 to n).foreach { _ =>
      gens.genTop(params, seed).foreach(r => typed(r).foreach(_ => count(r)))
      seed = seed.next
    }
    println(coverageLine)
    (generated.get >= n) :| "nothing generated" &&
      (discarded.get * 10 <= generated.get) :| ("discard rate above 10%: " + coverageLine) &&
      ctorCounts.synchronized {
        List("Filter", "Project", "JoinOn.Inner", "JoinOn.Left", "JoinOn.Full", "Union", "MinusI", "Except",
             "Combine", "RenameR", "Limit", "AggregateByGroup", "Aggregate", "LetR", "SmallLit", "RelEmpty")
          .map(k => (ctorCounts.contains(k) :| ("never generated: " + k))).reduce(_ && _)
      }
  }

  /** The typed relation, or `None` (a discard) when `Typer` rejects what the generator
    * believed was well-typed. */
  def typed(rel: Rel): Option[Header] = {
    generated.incrementAndGet()
    Typer.relTyper(rel).fold(e => {
      discarded.incrementAndGet()
      val k = e.head.take(80)
      discardReasons.synchronized { discardReasons(k) = discardReasons.getOrElse(k, 0) + 1 }
      None
    }, h => Some(h))
  }
  val discardReasons = scala.collection.mutable.Map[String, Int]()

  // ------------------------------------------------------------------ pinned examples

  import Op.{ ColumnValue, OpLiteral }
  private def i(n: Int) = IntExpr(false, n)
  private def lit(rows: Record*): Rel = SmallLit(NonEmptyList.nel(rows.head, scalaz.IList.fromList(rows.tail.toList)))

  /** Named relations that pin one finding each; `enabled(cls)` decides whether the
    * random generator may produce the class, the pin runs regardless and is expected
    * to FAIL against the compiler until an implementer fixes it (so each is registered
    * only under its flag, like the exclusions). */
  val pins: List[(String, String, Rel)] = List(
    ("O-1 outer join inside a let body compiles as an inner join (JoinOn.subst drops mode)", "letOuter",
     LetR(ExtRel(lit(Map("ia" -> i(1), "inl" -> IntExpr(true, 10))), ""), Nil,
          JoinOn(VarR(RTop), lit(Map("ia" -> i(2), "dn" -> DoubleExpr(true, 0.5))), Set(), JoinMode.Full))),
    ("O-2 a literal with duplicate rows scans with the duplicates (SQL Server TVC keeps them; the literal claims distinct)", "dupLit",
     lit(Map("ia" -> i(1)), Map("ia" -> i(1)))),
    ("O-3 outer join over a non-nullable header throws Unexpected NULL", "outerNull",
     JoinOn(lit(Map("ia" -> i(1), "ib" -> i(7))), lit(Map("ia" -> i(2), "da" -> DoubleExpr(false, 0.5))), Set(), JoinMode.Left)),
    ("O-4 SUM over an empty relation under a non-nullable attribute throws Unexpected NULL", "sumEmpty",
     Aggregate(RelEmpty(Map("ia" -> IntT(false))), Attribute("p1", IntT(false)), AggFunc.Sum(ColumnValue("ia", IntT(false))))),
    ("O-28 a FULL JOIN over a nullable key: the left-only and right-only rows coalesce to equal rows, the join claims distinctness, duplicates come out", "fullJoinNullKey",
     JoinOn(lit(Map("sn" -> NullExpr(StringT(0, true)))), lit(Map("sn" -> NullExpr(StringT(0, true)))), Set(), JoinMode.Full)),
    ("O-26 Limit(from = to > 1) takes the one-row shortcut and skips DISTINCT on its input: row 2 of a stream whose relation has one row", "limitOneRowOffset",
     Limit(Except(lit(Map("ta" -> DateExpr(false, YMDTriple(2024, 1, 2)), "ba" -> BooleanExpr(false, true), "inl" -> IntExpr(true, 0)),
                      Map("ta" -> DateExpr(false, YMDTriple(2024, 1, 2)), "ba" -> BooleanExpr(false, false), "inl" -> IntExpr(true, -1))), Set("ba", "inl")),
           Some(2), Some(2), List(("ta", Desc)))),
    ("O-27 a Limit ordering by an expression over an empty relation's constant NULL columns: SQL Server rejects the constant ORDER BY", "orderByConstExpr",
     Limit(Project(RelEmpty(Map("tn" -> DateT(true))),
                   Map(Attribute("tn", DateT(true)) -> (ColumnValue("tn", DateT(true)): Op),
                       Attribute("p5", StringT(0, false)) -> (Op.If(Predicate.Eq(ColumnValue("tn", DateT(true)), OpLiteral(DateExpr(false, YMDTriple(2024, 1, 2)))),
                                                                    OpLiteral(StringExpr(false, "a")), OpLiteral(StringExpr(false, "b"))): Op))),
           Some(1), Some(3), List(("p5", Asc), ("tn", Asc)))),
    ("O-25 a one-row literal's NULL is substituted into the filter as an untyped NULL; SQL Server rejects a CASE whose results are all NULL", "nullConstSubst",
     Filter(lit(Map("tn" -> NullExpr(DateT(true)))),
            Predicate.Eq(ColumnValue("tn", DateT(true)),
                         Op.If(Predicate.Lt(ColumnValue("tn", DateT(true)), ColumnValue("tn", DateT(true))), ColumnValue("tn", DateT(true)), ColumnValue("tn", DateT(true)))))),
    ("O-24 two columns with the same expression (two SUM inl) make a Limit order by the expression twice; SQL Server rejects the ORDER BY", "orderDupExpr",
     Limit(AggregateByGroup(lit(Map("inl" -> IntExpr(true, 1)), Map("inl" -> IntExpr(true, 2))), Map(),
                            List((Attribute("p1", IntT(true)), AggFunc.Sum(ColumnValue("inl", IntT(true)))),
                                 (Attribute("p6", IntT(true)), AggFunc.Sum(ColumnValue("inl", IntT(true))))), Nil),
           Some(1), Some(1), List(("p1", Desc), ("p6", Asc)))),
    ("O-23 string equality is case-insensitive in memory and in the compiler's constant folding (PrimExprOrder lower-cases): Eq(upper(sa), sa) over one row folds to TRUE", "mixedCase",
     Filter(lit(Map("sa" -> StringExpr(false, "a"))),
            Predicate.Eq(Op.BuiltinCall(Op.Upper, List(ColumnValue("sa", StringT(0, false)))), ColumnValue("sa", StringT(0, false))))),
    ("O-22 an empty relation is emitted as untyped NULL columns; SQL Server rejects MAX/MIN/SUM/AVG over them", "emptyAgg",
     Aggregate(RelEmpty(Map("tn" -> DateT(true))), Attribute("p1", DateT(true)), AggFunc.Max(ColumnValue("tn", DateT(true))))),
    ("O-22b a literal column that is all NULL is an untyped TVC column on SQL Server; MAX over it is rejected", "emptyAgg",
     Aggregate(lit(Map("sn" -> NullExpr(StringT(0, true)))), Attribute("p1", StringT(0, true)), AggFunc.Max(ColumnValue("sn", StringT(0, true))))),
    ("O-21 a double literal is emitted without an exponent and is DECIMAL on SQL Server: 1.0 / 3.0 answers 0.333333", "decimalLiteral",
     Project(lit(Map("da" -> DoubleExpr(false, 1.0))),
             Map(Attribute("p1", DoubleT(false)) -> (Op.DoubleDiv(ColumnValue("da", DoubleT(false)), OpLiteral(DoubleExpr(false, 3.0))): Op)))),
    ("O-16 (optimizer's) an if whose consequent is an if is merged into one CASE with not(test) first; an UNKNOWN test then falls through to the inner clauses", "ifNestedConsequent",
     Project(lit(Map("inl" -> NullExpr(IntT(true)))),
             Map(Attribute("p1", IntT(false)) -> (Op.If(Predicate.Gt(ColumnValue("inl", IntT(true)), OpLiteral(i(0))),
                                                        Op.If(Predicate.Gt(ColumnValue("inl", IntT(true)), OpLiteral(i(5))), OpLiteral(i(9)), OpLiteral(i(1))),
                                                        OpLiteral(i(5))): Op)))),
    ("O-15 a GROUP BY over columns that are constants at the select level is dropped: one row over an empty input instead of none", "groupByConst",
     AggregateByGroup(JoinOn(RelEmpty(Map("sn" -> StringT(0, true), "da" -> DoubleT(false))), lit(Map("sn" -> StringExpr(true, "a"))), Set(), JoinMode.Inner),
                      Map(Attribute("sn", StringT(0, true)) -> (ColumnValue("sn", StringT(0, true)): Op)),
                      List((Attribute("p1", IntT(false)), AggFunc.Count)),
                      List(ColumnValue("sn", StringT(0, true))))),
    ("O-14 a projection through a non-injective op (coalesce) is taken as distinctness-preserving: no DISTINCT, duplicate rows", "projectNonInjective",
     Project(lit(Map("sn" -> StringExpr(true, "b")), Map("sn" -> NullExpr(StringT(0, true)))),
             Map(Attribute("p2", StringT(0, false)) -> (Op.Coalesce(ColumnValue("sn", StringT(0, true)), OpLiteral(StringExpr(false, "b"))): Op)))),
    ("O-11 Eq(x, x) is simplified to TRUE; in SQL it is UNKNOWN when x is NULL, so the row is dropped", "eqSelf",
     Filter(lit(Map("inl" -> NullExpr(IntT(true)))), Predicate.Eq(ColumnValue("inl", IntT(true)), ColumnValue("inl", IntT(true))))),
    ("O-12 (lowering's) nested set operations are emitted without parentheses: A UNION B EXCEPT C is (A u B) - C on SQL Server", "setOpPrecedence",
     Union(lit(Map("ia" -> i(1)), Map("ia" -> i(2))),
           MinusI(lit(Map("ia" -> i(2)), Map("ia" -> i(3))), lit(Map("ia" -> i(2)))))),
    ("O-13 (lowering's) a two-row Limit (from, from+1) is taken for one row: the projection above it skips distinct and duplicates come out", "limitTwoRowsDistinct",
     Project(Limit(lit(Map("ia" -> i(1), "ib" -> i(1)), Map("ia" -> i(1), "ib" -> i(2)), Map("ia" -> i(2), "ib" -> i(3))),
                   Some(1), Some(2), List(("ib", Asc))),
             Map(Attribute("ia", IntT(false)) -> (ColumnValue("ia", IntT(false)): Op)))),
    ("O-10 a computed column on the unmatched side of an outer join is re-evaluated over NULLs instead of being NULL", "outerJoinInlinedExpr",
     JoinOn(lit(Map("ia" -> i(1))),
            Combine(lit(Map("ia" -> i(2))), Attribute("p1", StringT(0, true)), Op.Concat(List(OpLiteral(StringExpr(false, "x")), OpLiteral(StringExpr(false, "y"))))),
            Set(), JoinMode.Left)),
    ("O-9b (landing) a projection whose op mentions the aggregate column but FOLDS to a constant (if false ..) left having count(*) > 0 on a non-aggregate select", "projectOverAggConst",
     Project(Aggregate(RelEmpty(Map("da" -> DoubleT(false))), Attribute("p3", DoubleT(true)), AggFunc.Avg(ColumnValue("da", DoubleT(false)))),
             Map(Attribute("p5", DoubleT(true)) -> (Op.If(Predicate.Atom(false),
                                                          Op.Sub(ColumnValue("p3", DoubleT(true)), ColumnValue("p3", DoubleT(true))),
                                                          Op.DoubleDiv(OpLiteral(DoubleExpr(false, 1.0)), OpLiteral(DoubleExpr(false, 3.0)))): Op)))),
    ("O-9 a projection over an ungrouped aggregate that keeps no aggregate column loses the aggregate's one row", "projectOverAggConst",
     Project(Aggregate(RelEmpty(Map("ia" -> IntT(false))), Attribute("p1", IntT(false)), AggFunc.Count),
             Map(Attribute("p2", IntT(false)) -> (OpLiteral(i(3)): Op)))),
    ("O-8 a join whose right operand is a join is emitted right-nested without parentheses, which SQLite rejects", "nestedJoinRight",
     // two rows each: a ONE-row literal is squashed into the other side's select and never nests
     JoinOn(lit(Map("ia" -> i(1), "ib" -> i(2)), Map("ia" -> i(2), "ib" -> i(3))),
            JoinOn(lit(Map("ia" -> i(1), "da" -> DoubleExpr(false, 0.5)), Map("ia" -> i(2), "da" -> DoubleExpr(false, 1.5))),
                   lit(Map("ia" -> i(1), "sa" -> StringExpr(false, "a")), Map("ia" -> i(2), "sa" -> StringExpr(false, "b"))), Set(), JoinMode.Inner),
            Set(), JoinMode.Inner)),
    ("O-7 a Limit with a start and no end emits OFFSET without LIMIT, which SQLite rejects", "limitOffsetOnly",
     Limit(lit(Map("ia" -> i(1)), Map("ia" -> i(2)), Map("ia" -> i(3))), Some(2), None, List(("ia", Asc)))),
    ("O-6 a column named like a SQL keyword is emitted unquoted on SQLite", "keyword",
     lit(Map("in" -> i(1), "order" -> i(2)))),
    ("O-5 concat with a NULL: SQLite || answers NULL under a non-nullable header", "concatNull",
     Project(lit(Map("sn" -> NullExpr(StringT(0, true)), "sa" -> StringExpr(false, "a"))),
             Map(Attribute("p1", StringT(0, false)) -> Op.Concat(List(ColumnValue("sa", StringT(0, false)), ColumnValue("sn", StringT(0, true))))))))
}

/** The SQLite half: always registered, in `suites`. */
object TestSqlDifferential extends Properties("SQL differential oracle (in-memory SQLite)") {
  import SqlDifferential._

  override def overrideParameters(p: Test.Parameters): Test.Parameters =
    p.withMinSuccessfulTests(minTests(300)).withWorkers(1)

  private lazy val scanner = Scanners.SQLite(SMEnv.dummySmenv)
  private lazy val conn: Connection = { Class.forName("org.sqlite.JDBC"); DriverManager.getConnection("jdbc:sqlite::memory:") }
  private val gens = new Gens(Profile.sqlite)

  def check(rel: Rel): Prop = typed(rel) match {
    case None => Prop.undecided
    case Some(h) =>
      count(rel)
      val ref = try Right(Ref.eval[Nothing](rel, (x: Nothing) => x, (x: Nothing) => x)) catch { case e: Throwable => Left(e.toString) }
      ref match {
        case Left(e)  => Prop.falsified :| ("the reference evaluator threw " + e + "\nrelation: " + rel)
        case Right(r) => compare("sqlite", rel, h, r, scan(scanner, conn, rel))
      }
  }

  property("random relations: reference == SQLite") = forAll(gens.genTop)(check)

  pins.foreach { case (name, cls, rel) =>
    if (active(cls)) property("pin " + name) = secure(check(rel))
  }

  property("coverage: every constructor is generated, under 10% of candidates discarded") = secure(coverage(gens, 500))
}

/** The SQL Server half: registered only with `ERMINE_DB_*` in the environment (the
  * `db` gate), one connection for the suite, literal relations only so `ErmineSales`
  * at any tier will do; temp tables land in `tempdb`. */
object TestSqlDifferentialDb extends Properties("SQL differential oracle (SQL Server)") {
  import SqlDifferential._

  override def overrideParameters(p: Test.Parameters): Test.Parameters =
    p.withMinSuccessfulTests(minTests(150)).withWorkers(1)

  private val MsSqlDriver = "com.microsoft.sqlserver.jdbc.SQLServerDriver"
  private val env = sys.env
  private val creds = for {
    u  <- env.get("ERMINE_DB_URL").filter(_.nonEmpty)
    us <- env.get("ERMINE_DB_USER").filter(_.nonEmpty)
    pw <- env.get("ERMINE_DB_PASSWORD").filter(_.nonEmpty)
  } yield (TestMsSqlSmoke.withLocalTls(u), us, pw)

  creds match {
    case None =>
      // Registers NOTHING (the `suites` gate fails on a property named as
      // skipped, scripts/gates.sh); one info line says why, and the `db` gate
      // fails if it ever sees this line.
      println("[sqldiff] DB suites: not requested (no ERMINE_DB_* in the environment); the `db` gate runs them")
    case Some((url, user, password)) =>
      def scrub(s: String): String =
        if (s == null) "" else s.replace(password, "<password>").replace(url, "<url>")
      lazy val scanner = Scanners.MicrosoftSQLServer(SMEnv.dummySmenv)
      lazy val conn: Connection = { Class.forName(MsSqlDriver); DriverManager.getConnection(url, user, password) }
      val gens = new Gens(Profile.mssql)

      def tempTables(): Set[String] = {
        val st = conn.createStatement
        try {
          val rs = st.executeQuery("select name from tempdb.sys.tables where name like '##t%'")
          val b = Set.newBuilder[String]
          while (rs.next()) b += rs.getString(1)
          b.result()
        } finally st.close()
      }
      def check(rel: Rel): Prop = typed(rel) match {
        case None => Prop.undecided
        case Some(h) =>
          count(rel)
          val ref = try Right(Ref.eval[Nothing](rel, (x: Nothing) => x, (x: Nothing) => x)) catch { case e: Throwable => Left(e.toString) }
          ref match {
            case Left(e)  => Prop.falsified :| ("the reference evaluator threw " + scrub(e) + "\nrelation: " + rel)
            case Right(r) =>
              val s = scan(scanner, conn, rel)
              compare("mssql", rel, h, r, s.copy(rows = s.rows.left.map(scrub), sql = scrub(s.sql)))
          }
      }

      property("random relations: reference == SQL Server") = forAll(gens.genTop)(check)

      pins.foreach { case (name, cls, rel) =>
        if (active(cls)) property("pin " + name) = secure(check(rel))
      }


      /** sbt runs the properties of one suite in no fixed order (and concurrently), so
        * this one scans its OWN batch -- 40 candidates, every one wrapped in a let so a
        * temp table is created -- and counts tempdb's `##t` tables around it.  O-20:
        * `MsSqlEmitter` is `EmitNoDropTempTable`, so every `LetR` binding leaves its
        * GLOBAL temp table until the connection closes; until an implementer fixes it
        * the default property PINS that (one table per binding) and the clean assertion
        * runs under `letTemp`. */
      def letBindings[R](r: Relation[Nothing, R]): Int = r match {
        case LetR(ExtRel(b, _), _, e) => 1 + letBindings(b) + letBindings(e)
        case _ => children(r).map(letBindings(_)).sum
      }
      def tempScan(): (Int, Int, Set[String]) = scanLock.synchronized {
        val before = tempTables()
        val params = Gen.Parameters.default
        var seed = org.scalacheck.rng.Seed.random()
        var scanned = 0; var bindings = 0
        (1 to 40).foreach { _ =>
          gens.genTop(params, seed).foreach { r0 =>
            val r: Rel = LetR(ExtRel(r0, ""), Nil, VarR(RTop))
            if (typed(r).isDefined) { scanned += 1; bindings += letBindings(r); scan(scanner, conn, r) }
          }
          seed = seed.next
        }
        val mine = tempTables() -- before
        println("[sqldiff] mssql: " + before.size + " ##t tables in tempdb before, " + mine.size + " new after " + scanned +
                " let-wrapped scans holding " + bindings + " let bindings")
        (scanned, bindings, mine)
      }
      if (active("letTemp"))
        property("pin O-20 tempdb holds no ##t table this suite's scans created") = secure {
          val (scanned, _, mine) = tempScan()
          (scanned > 0) :| "nothing scanned" &&
            (mine.isEmpty :| ("temp tables left behind: " + mine.toList.sorted.take(10).mkString(", ")))
        }
      else
        property("O-20 (pinned as is): every LetR binding leaves one ##t global temp table in tempdb until the connection closes") = secure {
          val (scanned, bindings, mine) = tempScan()
          (scanned > 0) :| "nothing scanned" && ((mine.size ?= bindings) :| "temp tables left behind vs let bindings scanned")
        }
  }
}
