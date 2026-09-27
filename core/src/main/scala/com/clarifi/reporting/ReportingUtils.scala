package com.clarifi.reporting

import scalaz._
import Scalaz._
import scalaz.Scalaz._

import com.clarifi.reporting.Predicate._

/**
 * Collection of various utility and convenience methods that do not
 * have a good home.
 *
 * @author smb
 */
object ReportingUtils {
  /**
    * Simplifies a nested Predicate into something less nested; for
    * example it converts Not(Or(false, true)) -> false.
    *
    * @param p Predicate to simplify.
    * @param truth Guaranteed true about `p`'s domain.
    * @param falsehood Guaranteed false about `p`'s domain.
    * @note simplifyPredicate(p, t, f).eval(m) = p.eval(m)
    *       if `t`, `f` are sound.
    * @note Do not try `simplifyPredicate(p, Predicates constancies p)`.
    *       That just ties knots.
    */
  def simplifyPredicate(p: Predicate,
                        truth: Reflexivity[ColumnName] = Reflexivity.zero,
                        falsehood: Reflexivity[ColumnName] = Reflexivity.zero
                       ): Predicate = {
    import Predicate._
    // R10 (SQL audit O-25): a column known to be NULL is NOT substituted -- the untyped
    // NULL literal it would become makes SQL Server reject a CASE whose results are all
    // the NULL constant, and the column reference is right anyway.
    lazy val simplEnv = truth.consts collect {
      case (k, Some(v)) if !v.isNull => k -> Op.OpLiteral(v)
    }
    def rec(p: Predicate): Predicate = p match {
      case Lt(l, r) =>
        Lt(l simplify simplEnv, r simplify simplEnv)
      case Gt(l, r) =>
        Gt(l simplify simplEnv, r simplify simplEnv)
      case Eq(l, r) => (l simplify simplEnv, r simplify simplEnv) match {
        // R6 (SQL audit O-9/S-30): `x = x` is UNKNOWN in SQL when `x` is NULL, so the
        // fold to TRUE is only sound when the operand cannot be NULL by its own type.
        case (l, r) if l === r && !mayBeNull(l) => Atom(true)
        // R6: a singleton set is trivially "equivalent", so the same column on both sides
        // must not reach these two cases (it is the guarded case above).
        case (Op.ColumnValue(l, _), Op.ColumnValue(r, _))
            if l != r && (truth equivalent Set(l, r)) => Atom(true)
        case (Op.ColumnValue(l, _), Op.ColumnValue(r, _))
            if l != r && (falsehood equivalent Set(l, r)) => Atom(false)
        case (l, r) => Eq(l, r)
      }
      case Not(p) => rec(p) match {
        case Atom(b) => Atom(!b)
        case Not(p2) => p2
        case p2 => Not(p2)
      }
      case Or(a, b) => (rec(a), rec(b)) match {
        case (Atom(true), _) => Atom(true)
        case (_, Atom(true)) => Atom(true)
        case (Atom(false), b2) => b2
        case (a2, Atom(false)) => a2
        case (a2, b2) => Or(a2, b2)
      }
      case And(a, b) => (rec(a), rec(b)) match {
        case (Atom(false), _) => Atom(false)
        case (_, Atom(false)) => Atom(false)
        case (Atom(true), b2) => b2
        case (a2, Atom(true)) => a2
        case (a2, b2) => And(a2, b2)
      }
      case _ => p
    }
    rec(p)
  }

  /** Whether `op` may evaluate to NULL, by its guessed type: a nullable column, a NULL
    * literal, an expression over either; an op that does not type is taken as nullable. */
  def mayBeNull(op: Op): Boolean = op match {
    case Op.OpLiteral(v) => v.isNull   // a NULL literal whatever its declared type says
    case _ => op.guessType.fold(_ => true, _.nullable)
  }

  /** R5 (SQL audit O-6/S-25): the predicate that is TRUE exactly when `p` is NOT TRUE
    * under SQL's three-valued logic (FALSE or UNKNOWN), and always definite itself:
    *
    *   notTrue(a < b)      = NOT (a < b) OR a IS NULL OR b IS NULL   (a comparison is UNKNOWN
    *                                                                 iff an operand is NULL)
    *   notTrue(a OR b)     = notTrue(a) AND notTrue(b)
    *   notTrue(a AND b)    = notTrue(a) OR notTrue(b)
    *   notTrue(NOT a)      = notFalse(a)
    *   notTrue(x IS NULL)  = NOT (x IS NULL)                          (never UNKNOWN)
    *
    * and `notFalse` dually (TRUE or UNKNOWN).  A NULL test is left out for an operand
    * that is a non-NULL literal.  Column operands keep their test whatever their declared
    * type says: after an `unsafe*` outer join the surface type is not nullable while the
    * column is.  `None` for a `Funtest`, whose truth table is the database's.
    * `difference (filter p1 r) (filter p2 r)` is `filter (p1 AND notTrue(p2)) r` exactly,
    * because a row of `r` is in the right side iff `p2` is TRUE of it. */
  def notTrue(p: Predicate): Option[Predicate] = {
    def nulls(l: Op, r: Op): List[Predicate] =
      List(l, r) collect { case o if !definite(o) => IsNull(o) }
    def definite(o: Op): Boolean = o match {
      case Op.OpLiteral(v) => !v.isNull
      case _ => false
    }
    def orAll(p: Predicate, ps: List[Predicate]): Predicate = ps.foldLeft(p)(Or(_, _))
    def nt(p: Predicate): Option[Predicate] = p match {
      case Atom(b)          => Some(Atom(!b))
      case Lt(l, r)         => Some(orAll(Not(p), nulls(l, r)))
      case Gt(l, r)         => Some(orAll(Not(p), nulls(l, r)))
      case Eq(l, r)         => Some(orAll(Not(p), nulls(l, r)))
      case IsNull(_)        => Some(Not(p))
      case Or(a, b)         => for (x <- nt(a); y <- nt(b)) yield And(x, y)
      case And(a, b)        => for (x <- nt(a); y <- nt(b)) yield Or(x, y)
      case Not(q)           => nf(q)
      case Funtest(_, _, _, _) => None
    }
    def nf(p: Predicate): Option[Predicate] = p match {
      case Atom(b)          => Some(Atom(b))
      case Lt(l, r)         => Some(orAll(p, nulls(l, r)))
      case Gt(l, r)         => Some(orAll(p, nulls(l, r)))
      case Eq(l, r)         => Some(orAll(p, nulls(l, r)))
      case IsNull(_)        => Some(p)
      case Or(a, b)         => for (x <- nf(a); y <- nf(b)) yield Or(x, y)
      case And(a, b)        => for (x <- nf(a); y <- nf(b)) yield And(x, y)
      case Not(q)           => nt(q)
      case Funtest(_, _, _, _) => None
    }
    nt(p)
  }

  /**
   * Builds a predicate from a header. If there is more than one header, the
   * other function, g, determines how to combine predicates.
   */
  def buildPredicate[A](l: List[A], f: A => Predicate, g: (Predicate, Predicate) => Predicate): Predicate = l match {
    case h :: Nil => f(h)
    case h :: t => g(f(h), buildPredicate(t, f, g))
    case _ => sys.error("Cannot build predicate for unexpected empty header.")
  }

  /** Partition contiguous sequences of `xs` values with equal `kf`
    * results. */
  def splitWith[A, B](xs: Seq[A])(pf: PartialFunction[A,B]): Seq[Either[Seq[B], Seq[A]]] = {
    @annotation.tailrec
    def loop(acc: Vector[Either[Seq[B], Seq[A]]], s: Seq[A]): Seq[Either[Seq[B], Seq[A]]] = {
      if (s.isEmpty) acc
      else if (pf.isDefinedAt(s.head)) {
        val (pre, post) = s.span(pf.isDefinedAt)
        loop(acc :+ Left(pre.map(pf)), post)
      } else {
        val (pre, post) = s.span(!pf.isDefinedAt(_))
        loop(acc :+ Right(pre), post)
      }
    }
    loop(Vector(), xs)
  }

  /** The entirely safe reduction of `xs`. */
  def foldNel[X](xs: NonEmptyList[X])(f: (X, X) => X) =
    xs.tail.foldLeft(xs.head)(f)

  /** Reduce with log₂n append depth. */
  def binaryReduce[X](xs: Iterable[X])(f: (X, X) => X): Option[X] =
    if (xs isEmpty) None else {
      @annotation.tailrec
      def pass(xs: Stream[X]): X = xs match {
        case Stream(x) => x
        case xs => pass(xs grouped 2 map {case Seq(a, b) => f(a, b)
                                          case Seq(a) => a} toStream)
      }
      Some(pass(xs toStream))
    }

  // In general, java.text Formatters don't promise reentrancy, so we
  // work around that.
  def threadLocal[A](geta: => A): ThreadLocal[A] = new ThreadLocal[A] {
    override def initialValue = geta
  }

  object MapElts {
    /** Destructure a map.  Only really works with zero or one element
      * maps. */
    def unapplySeq[K, V](m: Map[K, V]) = Some(m.toSeq)
  }

  /**
   * Various methods to repeat a blank space some number of times and
   * optionally add additional items after that.
   */
  def padding(level: Int): Cord = List.fill(level)(" ").mkString("")
  def paddingRel(level: Int): Cord = padding(level) |+| "Relation(\n"
  def paddingVar(level: Int): Cord = padding(level) |+| "Variable("

  def prettyOp(o: Op, level: Int): Cord = {
    import com.clarifi.reporting.Op._
    padding(level) |+| implicitly[Show[Op]].show(o)
  }

  def prettyPredicate(p: Predicate, level: Int): Cord = {
    def binop(lbl: String, s1: Op, s2: Op): Cord =
      padding(level) |+| lbl |+| "(\n" |+|
      prettyOp(s1, level + 2) |+|
      padding(level + 2) |+| ",\n" |+|
      prettyOp(s2, level + 2) |+|
      padding(level) |+| ")\n"
    p match {
      case Atom(b) => padding(level) |+| "Atom(" |+| b.show |+| ")\n"
      case Lt(s1, s2) => binop("Lt", s1, s2)
      case Gt(s1, s2) => binop("Gt", s1, s2)
      case Eq(s1, s2) => binop("Eq", s1, s2)
      case Not(p) => {
        padding(level) |+| "Not(\n" |+|
        prettyPredicate(p, level + 2) |+|
        padding(level) |+| ")\n"
      }
      case Or(p1, p2) => {
        padding(level) |+| "Or(\n" |+|
        prettyPredicate(p1, level + 2) |+|
        padding(level + 2) |+| ",\n" |+|
        prettyPredicate(p2, level + 2) |+|
        padding(level) |+| ")\n"
      }
      case And(p1, p2) => {
        padding(level) |+| "And(\n" |+|
        prettyPredicate(p1, level + 2) |+|
        padding(level + 2) |+| ",\n" |+|
        prettyPredicate(p2, level + 2) |+|
        padding(level) |+| ")\n"
      }
      case _ => sys.error("Predicate unsupported: " + p)
    }
  }

  def prettyRelationHeader(h: Header, level: Int): Cord = {
    import com.clarifi.reporting.PrimT

    def printHeader(l: List[(String, PrimT.Type)], level: Int): Cord = {
      l match {
        case (c, t) :: Nil => {
          padding(level) |+| implicitly[Show[String]].show(c) |+|
            " -> " |+| implicitly[Show[PrimT.Type]].show(t) |+| "\n"
        }
        case (c, t) :: tail => {
          padding(level) |+| implicitly[Show[String]].show(c) |+|
            " -> " |+| implicitly[Show[PrimT.Type]].show(t) |+| ",\n" |+|
          printHeader(tail, level)
        }
        case _ => padding(level)
      }
    }

    padding(level) |+| "Map(\n" |+|
    printHeader(h.toList, level + 2) |+|
    padding(level) |+| "),\n"
  }
}
