package com.clarifi.reporting.sql

import math.Ordering
import scalaz._
import Scalaz._

/** The ultimate output of a SQL code generator. */
case class RawSql(private[RawSql] val contents: Vector[String]) {
  private[RawSql] lazy val stringValue = contents.mkString

  /** Produce the raw SQL, and any secondary data it may require. */
  def run: String = stringValue

  def isEmpty = contents.filter(_ != "").isEmpty
}

object RawSql {
  /** Produce a raw given some SQL. */
  implicit def raw(v: String) = RawSql(Vector(v))
  def raw[F[_]: Foldable](vs: F[String]) = RawSql(vs.foldLeft(Vector[String]())((a, b) => a :+ b))

  /** Raw is a monoid, can be shown, and can be ordered with respect to
    * its literal, unparameterized SQL content.
    */
  implicit object rawInstance extends Monoid[RawSql] with Show[RawSql] with Order[RawSql] {
    import std.vector._

    // monoid
    def append(left: RawSql, right: => RawSql) =
      RawSql(left.contents |+| right.contents)
    val zero = raw("")

    // show
    override def show(r: RawSql) = Cord("RawSql") |+| r.contents.show

    // order
    def order(left: RawSql, right: RawSql) = left.stringValue ?|? right.stringValue
  }

  /** Raws can be interposed with strings. */
  implicit final class RawStringJoins[F[_]](val value: F[RawSql]) extends AnyVal {
    /** Like `mkString`, but for joining raws safely. */
    def rawMkString(join: String)(implicit ev: Foldable[F]) =
      value intercalate raw(join)
    /** Like `mkString`, but for joining raws safely. */
    def rawMkString(left: String, join: String, right: String
                   )(implicit ev: Foldable[F]) =
      raw(left) |+| (value intercalate raw(join)) |+| raw(right)
  }

  /** Raws can be laid out against format strings. */
  implicit final class RawFormatter(val value: String) extends AnyVal {
    /** Combine `raws` with a `formatSpec`.  The consequences of not
      * including enough directives to consume all `raws` are not
      * nice.
      */
    def formatRaws(raws: RawSql*) = raw(value format ((raws map (_.stringValue)): _*))
  }

  /** Scala compatibility. */
  private[sql] implicit val rawOrdering: Ordering[RawSql] =
    rawInstance.toScalaOrdering
}
