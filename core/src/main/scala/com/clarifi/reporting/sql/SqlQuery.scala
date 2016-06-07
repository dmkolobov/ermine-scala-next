package com.clarifi.reporting.sql

import scala.collection.{AbstractSeq, LinearSeq}

import scalaz._
import Scalaz._
import Equal._
import Show._

import com.clarifi.reporting.{ Header, TableHints, Hints, TableName }

/*
package namespace {
  sealed abstract class Namespace[+T] {
    protected[namespace] val taken: Set[T]

    private[namespace] type Injects

    class Name protected[namespace](val name: T) {}

    def alloc[U >: T](name: U): Option[SingletonNamespace[U, this.type]] = {
      if (fresh(name)) {
        Some(new SingletonNamespace[U, this.type](name, this))
      } else {
        None
      }
    }

    def fresh[U >: T](name: U): Boolean = { !taken.toSet[U](name) }
  }

  sealed class RestrictedNamespace[+T] extends Namespace[T] {
    type Buddy <: Namespace[T]
    def buddy: Buddy
  }

  object EmptyNamespace extends RestrictedNamespace[Nothing] {
    type Buddy = this.type
    override def buddy = this
    override val taken = Set()
  }

  final class SingletonNamespace[+T, B <: Namespace[T]] private[namespace](nm: T, override val buddy: B) extends RestrictedNamespace[T] {
    type Buddy = B
    val name: Name = new Name(nm)
    override val taken = buddy.taken + nm
  }

  class UnionedNamespace[+T, B <: Namespace[T], L <: RestrictedNamespace[T] { type Buddy = B }] private[namespace](left: L, right: RestrictedNamespace[T] { type Buddy = L }) extends RestrictedNamespace[T] {
    type Buddy = B
    override val buddy = left.buddy
    override val taken = right.taken
  }
}

import namespace.{Namespace, EmptyNamespace}
*/

sealed abstract class SqlQuery {

  import RawSql._
  import scalaz.std.iterable._

  def emitSql(implicit emitter: SqlEmitter): RawSql = this match {
    case SqlSelect(options, attrs, sources, criteria, groupBy, orderBy, limit) =>
      raw("select ") |+|
      (if (options contains "distinct") raw("distinct ") else raw("")) |+|
      { if (attrs.isEmpty) "*"
        else (attrs.toIndexedSeq.sortBy((_: (SqlColumn, SqlExpr))._1)
              .map(x => raw("(") |+| x._2.emitSql |+| ") " |+|
                   emitter.emitColumnName(x._1)).rawMkString(", ")) } |+|
      (if (!sources.isEmpty) {
        raw(" from ") |+| sources.map(x => x.emitSql).toIterable.rawMkString(", ")
                                 } else emitter.emitFromEmptyTable ) |+|
      (if (!criteria.isEmpty)
        raw(" where ") |+| criteria.map(x => raw("(") |+| x.emitSql |+| ")").toIterable.rawMkString(" and ")
      else raw("")) |+|
      (if (!groupBy.isEmpty)
        raw(" group by ") |+| (groupBy.toIndexedSeq.map((x: SqlExpr) => x.emitSql).rawMkString(", "))
      else raw("")) |+|
      (if (!orderBy.isEmpty)
        raw(" order by ") |+|
        orderBy.distinct.map(x =>
          emitter.emitBinaryOrdering(x._3, x._1.emitSql) |+| " " |+|
          x._2.emitSql
        ).toIterable.rawMkString(", ")
      else raw("")) |+|
      (limit match { case (from, to) =>
        emitter.emitLimitClause(from, to)})
    case SqlNaryOp(op, rs) =>
      emitter.emitNaryOp(op, rs)
    case SqlExcept(left, unLeft, right, unRight, rheader) =>
      emitter.emitExcept(left, unLeft, right, unRight, rheader)
    case SqlEmpty(h) => emitter.emitEmpty(h)
    case LiteralSqlTable(nel) => emitter.emitLiteral(nel)
  }
}

object SqlQuery {
  implicit val SqlQueryShow: Show[SqlQuery] = showA[SqlQuery]
  implicit val SqlQueryEqual: Equal[SqlQuery] = equalA[SqlQuery]
}

sealed abstract class SqlSource {
  import RawSql._

  /**
   * Gives the fully-qualified name to refer to a virtual column name.
   */
  val columnMap: Map[SqlColumn, (TableName, SqlColumn)]

  def emitSql(implicit emitter: SqlEmitter): RawSql = this match {
    case SqlJoinOn(r1, r2, ons, op) =>
      emitter.emitJoinOn(r1, r2, ons.map {case (x, y) => (r1.columnMap(x),r2.columnMap(y))}, op)
    case FromTable(t, _, None) => emitter.emitTableName(t)
    case FromTable(t, _, Some(alias)) => emitter.emitTableName(t) |+| " " |+| emitter.emitTableName(alias)
    case SqlSubquery(q, _, alias) => raw("(") |+| q.emitSql |+| ") " |+| emitter.emitTableName(alias)
  }
}

object SqlSource {
  implicit val SqlSourceShow: Show[SqlSource] = showA[SqlSource]
  implicit val SqlSourceEqual: Equal[SqlSource] = equalA[SqlSource]
}

final case class SourceList(sources: List[SqlSource]) {
  lazy val columnMap: Map[SqlColumn, (TableName, SqlColumn)] =
    sources.foldLeft(Map[SqlColumn, (TableName,SqlColumn)]())((r, x) => x.columnMap ++ r)
}

object SourceList {
  implicit def sources(sl : SourceList): List[SqlSource] = sl.sources
  
  def apply(sources: SqlSource*): SourceList = SourceList(sources.toList)
}

case class SqlSelect(options: Set[String] = Set(), // Distinct, all, etc.  FIXME use enum
                     attrs: Map[SqlColumn, SqlExpr] = Map(), // result attributes
                     sources: SourceList = SourceList(), // from clause
                     criteria: List[SqlPredicate] = List(), // where clause
                     groupBy: List[SqlExpr] = List(), // groupBy clause
                     orderBy: List[(SqlExpr, SqlOrder, Boolean)] = List(),
                     // limit clause (where allowed), inclusive 1-indexed (from, to)
                     limit: (Option[Int], Option[Int]) = (None, None)
                    ) extends SqlQuery

case class LiteralSqlTable(lit: NonEmptyList[Map[SqlColumn, SqlExpr]]) extends SqlQuery

sealed abstract class SqlBinOp {
  def emit: RawSql = this match {
    case SqlUnion => "UNION"
    case SqlIntersect => "INTERSECT"
  }
}
case object SqlUnion extends SqlBinOp {
  def apply(r1: SqlQuery, r2: SqlQuery) = (r1, r2) match {
    case (SqlNaryOp(SqlUnion, xs), SqlNaryOp(SqlUnion, ys)) =>
      SqlNaryOp(SqlUnion, xs append ys)
    case (SqlNaryOp(SqlUnion, xs), _) => SqlNaryOp(SqlUnion, xs append NonEmptyList(r2))
    case (_, SqlNaryOp(SqlUnion, ys)) => SqlNaryOp(SqlUnion, r1 <:: ys)
    case _ => SqlNaryOp(SqlUnion, NonEmptyList(r1, r2))
  }
}
case object SqlIntersect extends SqlBinOp {
  def apply(r1: SqlQuery, r2: SqlQuery) = (r1, r2) match {
    case (SqlNaryOp(SqlIntersect, xs), SqlNaryOp(SqlIntersect, ys)) =>
      SqlNaryOp(SqlIntersect, xs append ys)
    case (SqlNaryOp(SqlIntersect, xs), _) => SqlNaryOp(SqlIntersect, xs append NonEmptyList(r2))
    case (_, SqlNaryOp(SqlIntersect, ys)) => SqlNaryOp(SqlIntersect, r1 <:: ys)
    case _ => SqlNaryOp(SqlIntersect, NonEmptyList(r1, r2))
  }
}

// Union relational operator
case class SqlNaryOp(op: SqlBinOp, rs: NonEmptyList[SqlQuery]) extends SqlQuery

sealed abstract class SqlJoinOp {
  def emit: RawSql = this match {
    case SqlJoinInner => "JOIN"
    case SqlJoinLeft => "LEFT JOIN"
    case SqlJoinRight => "RIGHT JOIN"
    case SqlJoinFull => "FULL JOIN"
  }
}

case object SqlJoinInner extends SqlJoinOp
case object SqlJoinLeft  extends SqlJoinOp
case object SqlJoinRight extends SqlJoinOp
case object SqlJoinFull  extends SqlJoinOp

case class SqlJoinOn(r1: SqlSource, r2: SqlSource, on: Set[(SqlColumn, SqlColumn)], op: SqlJoinOp = SqlJoinInner) extends SqlSource {
  override val columnMap = r2.columnMap ++ r1.columnMap
}

// Operator for except, which only exists in some dialects and is worked around in others
case class SqlExcept(left: SqlQuery, unLeft: TableName, right: SqlQuery, unRight: TableName, rheader: Header) extends SqlQuery

// A table with no rows
case class SqlEmpty(h: Header) extends SqlQuery

// select from table.  We assume that `cols` lists every column in
// `table`.
case class FromTable(table: TableName, cols: List[SqlColumn], alias: Option[TableName]) extends SqlSource {
  override val columnMap = cols.map(c => c -> (alias.getOrElse(table), c)).toMap
}

// subquery as a FROM clause element.  We assume that `cols` lists
// every column in `query`.
case class SqlSubquery(query: SqlQuery, cols: List[SqlColumn], alias: TableName) extends SqlSource {
  override val columnMap = cols.map(c => c -> (alias, c)).toMap
}
