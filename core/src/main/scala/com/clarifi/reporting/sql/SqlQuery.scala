package com.clarifi.reporting.sql

import scalaz._
import Scalaz._
import Equal._
import Show._

import com.clarifi.reporting.{ Header, TableHints, Hints, TableName }

sealed abstract class SqlQuery {

  import RawSql._
  import scalaz.std.iterable._

  def emitSql(implicit emitter: SqlEmitter): RawSql = this match {
    case SqlSelect(options, attrs, sources, where, groupBy, having, _, _) =>
      raw("select ") |+|
      (if (options contains "distinct") raw("distinct ") else raw("")) |+|
      { if (attrs.isEmpty) "*"
        else (attrs.toIndexedSeq.sortBy((_: (SqlColumn, SqlExpr))._1)
              .map(x => raw("(") |+| x._2.emitSql |+| ") " |+|
                   emitter.emitColumnName(x._1)).rawMkString(", ")) } |+|
      (if (!sources.isEmpty) {
        raw(" from ") |+| sources.map(x => x.emitSql).toIterable.rawMkString(", ")
                                 } else emitter.emitFromEmptyTable ) |+|
      (if (!where.isEmpty)
        raw(" where ") |+| where.map(x => raw("(") |+| x.emitSql |+| ")").toIterable.rawMkString(" and ")
      else raw("")) |+|
      (if (!groupBy.isEmpty)
        raw(" group by ") |+| (groupBy.toIndexedSeq.map((x: SqlExpr) => x.emitSql).rawMkString(", "))
      else raw("")) |+|
      (if (!having.isEmpty)
        raw(" having ") |+| having.map(x => raw("(") |+| x.emitSql |+| ")").toIterable.rawMkString(" and ")
      else raw(""))
    case SqlNaryOp(op, rs) =>
      emitter.emitNaryOp(op, rs)
    case SqlExcept(left, unLeft, right, unRight, rheader) =>
      emitter.emitExcept(left, unLeft, right, unRight, rheader)
    case SqlEmpty(h) => emitter.emitEmpty(h)
    case LiteralSqlTable(nel) => emitter.emitLiteral(nel)
    case SqlOrderBy(q, orderBy) =>
      q.emitSql |+|
      raw(" order by ") |+|
      (if (orderBy.isEmpty) raw("1 asc")
        else orderBy.distinct.map(x =>
          emitter.emitColumnName(x._1) |+| " " |+|
          x._2.emitSql
        ).toIterable.rawMkString(", "))
    case SqlOrderByExpr(q, orderBy) =>
      q.emitSql |+|
      raw(" order by ") |+| {
        val realOrder = orderBy filter {
          i => i._1.deparenthesize match {
            case LitSqlExpr(_) => false
            case _ => true
          }
          // XXX could still fail if it's constant -- check for this?
        }
        if (realOrder.isEmpty) raw("1 asc")
          else realOrder.distinct.map(x =>
            x._1.emitSql |+| " " |+|
            x._2.emitSql
          ).toIterable.rawMkString(", ")
      }
    case SqlLimit(q, from, to) =>
      (from, to) match {
        // always emit a limit clause even if it's trivial; this affects parsing.
        case (None, None) => q.emitSql |+| emitter.emitLimit(Some(1), None)
        case _ =>            q.emitSql |+| emitter.emitLimit(from, to)
      }
  }
}

object SqlQuery {
  implicit val SqlQueryShow: Show[SqlQuery] = showA[SqlQuery]
  implicit val SqlQueryEqual: Equal[SqlQuery] = equalA[SqlQuery]

  sealed trait Scannable extends SqlQuery
  sealed trait Orderable extends SqlQuery
  sealed trait Limitable extends SqlQuery
  sealed trait Nestable extends SqlQuery

  def orderBy(q: SqlQuery.Orderable, orderBy: List[(SqlColumn, SqlOrder)]) = q match {
    case sel: SqlSelect => SqlOrderByExpr(sel, orderBy map { case (c,o) => (sel.attrs(c),o) })
    case unsel => SqlOrderBy(unsel, orderBy)
  }
}

sealed abstract class SqlSource {
  import RawSql._

  def emitSql(implicit emitter: SqlEmitter): RawSql = this match {
    case SqlJoinOn(r1, r2, ons, op) =>
      emitter.emitJoinOn(r1, r2, ons, op)
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
  def asSource: Option[SqlSource] = sources.foldRight[Option[SqlSource]](None) {
    (x,y) =>
      y match {
        case None => Some(x)
        case Some(yy) => Some(SqlJoinOn(x,yy,Set(),SqlJoinInner))
      }
  }
  def isEmpty = sources.isEmpty
}

object SourceList {
  implicit def sources(sl : SourceList): List[SqlSource] = sl.sources
  
  def apply(sources: SqlSource*): SourceList = SourceList(sources.toList)
}

case class SqlSelect(options: Set[String] = Set(), // Distinct, all, etc.  FIXME use enum
                     attrs: Map[SqlColumn, SqlExpr] = Map(), // result attributes
                     sources: SourceList = SourceList(), // from clause
                     where: List[SqlPredicate] = List(), // where clause
                     groupBy: List[SqlExpr] = List(), // groupBy clause
                     having: List[SqlPredicate] = List(), // having clause
                     // limit clause (where allowed), inclusive 1-indexed (from, to)
                     isAggregated: Boolean = false,
                     windowColumns: Set[SqlColumn] = Set()
                    ) extends SqlQuery with SqlQuery.Scannable with SqlQuery.Orderable with SqlQuery.Nestable {
  def isWindowed = windowColumns.nonEmpty
}

object SqlSingle {
  type SqlRecord = Map[SqlColumn, LitSqlExpr]
  def apply(r: SqlRecord) = SqlSelect(attrs = r)
  def unapply(q: SqlQuery): Option[SqlRecord] = q match {
    case sel : SqlSelect =>
      if(sel.sources.isEmpty && sel.where.isEmpty && !sel.isAggregated)
        sel.attrs.foldLeft(Some(Map()):Option[SqlRecord]) {
          case (r, (c, e : LitSqlExpr)) => r.map(_ + (c -> e))
          case _ => None
        }
      else None
    case LiteralSqlTable(nel) if nel.tail.isEmpty => Some(nel.head)
    case _ => None
  }
}

case class LiteralSqlTable(lit: NonEmptyList[Map[SqlColumn, LitSqlExpr]]) extends SqlQuery with SqlQuery.Scannable with SqlQuery.Orderable with SqlQuery.Nestable

sealed abstract class SqlBinOp {
  def emit: RawSql = this match {
    case SqlUnion => "UNION"
    case SqlIntersect => "INTERSECT"
  }
}
case object SqlUnion extends SqlBinOp {
  def apply(r1: SqlQuery.Orderable, r2: SqlQuery.Orderable) = (r1, r2) match {
    case (SqlNaryOp(SqlUnion, xs), SqlNaryOp(SqlUnion, ys)) =>
      SqlNaryOp(SqlUnion, xs append ys)
    case (SqlNaryOp(SqlUnion, xs), _) => SqlNaryOp(SqlUnion, xs append NonEmptyList(r2))
    case (_, SqlNaryOp(SqlUnion, ys)) => SqlNaryOp(SqlUnion, r1 <:: ys)
    case _ => SqlNaryOp(SqlUnion, NonEmptyList(r1, r2))
  }
}
case object SqlIntersect extends SqlBinOp {
  def apply(r1: SqlQuery.Orderable, r2: SqlQuery.Orderable) = (r1, r2) match {
    case (SqlNaryOp(SqlIntersect, xs), SqlNaryOp(SqlIntersect, ys)) =>
      SqlNaryOp(SqlIntersect, xs append ys)
    case (SqlNaryOp(SqlIntersect, xs), _) => SqlNaryOp(SqlIntersect, xs append NonEmptyList(r2))
    case (_, SqlNaryOp(SqlIntersect, ys)) => SqlNaryOp(SqlIntersect, r1 <:: ys)
    case _ => SqlNaryOp(SqlIntersect, NonEmptyList(r1, r2))
  }
}

// Union relational operator
case class SqlNaryOp(op: SqlBinOp, rs: NonEmptyList[SqlQuery.Orderable]) extends SqlQuery with SqlQuery.Scannable with SqlQuery.Orderable with SqlQuery.Nestable

case class SqlOrderBy(q: SqlQuery.Orderable,
                      orderBy: List[(SqlColumn, SqlOrder)]) extends SqlQuery with SqlQuery.Scannable with SqlQuery.Limitable

case class SqlOrderByExpr(q: SqlQuery.Orderable,
                          orderBy: List[(SqlExpr, SqlOrder)]) extends SqlQuery with SqlQuery.Scannable with SqlQuery.Limitable

case class SqlLimit(q: SqlQuery.Limitable,
                    from: Option[Int] = None,
                    to: Option[Int] = None) extends SqlQuery with SqlQuery.Scannable with SqlQuery.Nestable

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

case class SqlJoinOn(r1: SqlSource, r2: SqlSource, on: Set[(SqlExpr, SqlExpr)], op: SqlJoinOp = SqlJoinInner) extends SqlSource

// Operator for except, which only exists in some dialects and is worked around in others
case class SqlExcept(left: SqlQuery.Orderable, unLeft: TableName, right: SqlQuery.Orderable, unRight: TableName, rheader: Header) extends SqlQuery with SqlQuery.Scannable with SqlQuery.Orderable with SqlQuery.Nestable

// A table with no rows
case class SqlEmpty(h: Header) extends SqlQuery with SqlQuery.Scannable with SqlQuery.Orderable with SqlQuery.Nestable

// select from table.  We assume that `cols` lists every column in
// `table`.
case class FromTable(table: TableName, cols: List[SqlColumn], alias: Option[TableName]) extends SqlSource

// subquery as a FROM clause element.  We assume that `cols` lists
// every column in `query`.
case class SqlSubquery(query: SqlQuery.Nestable, cols: List[SqlColumn], alias: TableName) extends SqlSource
