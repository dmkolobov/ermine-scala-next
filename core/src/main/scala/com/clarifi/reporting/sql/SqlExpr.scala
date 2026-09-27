package com.clarifi.reporting
package sql

import java.util.{Date,UUID}
import scalaz._
import scalaz.Scalaz._

import com.clarifi.reporting.{ Header, TableName }

import RawSql._

sealed abstract class SqlOrder {
  def emitSql: RawSql = this match {
    case SqlAsc => "asc"
    case SqlDesc => "desc"
  }
}
case object SqlAsc extends SqlOrder
case object SqlDesc extends SqlOrder

sealed abstract class SqlPredicate {
  import scalaz.std.iterable._

  /** Emit a predicate for a where clause */
  def emitSql(implicit emitter: SqlEmitter): RawSql = this match {
    case SqlTruth(t) => if (t) "'A' = 'A'" else "'A' = 'B'"
    case SqlLt(a, b) => raw("(") |+| a.emitSql(emitter) |+| ") < (" |+| b.emitSql(emitter) |+| ")"
    case SqlGt(a, b) => raw("(") |+| a.emitSql(emitter) |+| ") > (" |+| b.emitSql(emitter) |+| ")"
    case SqlEq(a, b) => raw("(") |+| a.emitSql(emitter) |+| ") = (" |+| b.emitSql(emitter) |+| ")"
    case SqlLte(a, b) => raw("(") |+| a.emitSql(emitter) |+| ") <= (" |+| b.emitSql(emitter) |+| ")"
    case SqlGte(a, b) => raw("(") |+| a.emitSql(emitter) |+| ") >= (" |+| b.emitSql(emitter) |+| ")"
    case SqlNot(a) => raw("not (") |+| a.emitSql(emitter) |+| ")"
    case SqlOr(h, t @ _*) => raw("(") |+| t.foldLeft(h.emitSql(emitter))((a, b) =>
      a |+| " or " |+| b.emitSql(emitter)) |+| raw(")")
    case SqlAnd(h, t @ _*) => raw("(") |+| t.foldLeft(h.emitSql(emitter))((a, b) =>
      a |+| " and " |+| b.emitSql(emitter)) |+| raw(")")
    case SqlIsNull(e) => raw("(") |+| e.emitSql(emitter) |+| ") is null"
    case ExistsSqlExpr(query) => raw("exists ") |+| query.emitSql(emitter)
    case SqlFun(fn, args) => raw(fn) |+| "(" |+| args.map(_.emitSql(emitter)).toIterable.rawMkString(", ") |+| ")"
  }
}
case class SqlTruth(truth: Boolean) extends SqlPredicate
case class SqlLt(left: SqlExpr, right: SqlExpr) extends SqlPredicate
case class SqlGt(left: SqlExpr, right: SqlExpr) extends SqlPredicate
case class SqlEq(left: SqlExpr, right: SqlExpr) extends SqlPredicate
case class SqlLte(left: SqlExpr, right: SqlExpr) extends SqlPredicate
case class SqlGte(left: SqlExpr, right: SqlExpr) extends SqlPredicate
case class SqlNot(p: SqlPredicate) extends SqlPredicate
case class SqlOr(ps: SqlPredicate*) extends SqlPredicate
case class SqlAnd(ps: SqlPredicate*) extends SqlPredicate
case class SqlIsNull(expr: SqlExpr) extends SqlPredicate
case class ExistsSqlExpr(query: SqlQuery) extends SqlPredicate
case class SqlFun(f: String, args: List[SqlExpr]) extends SqlPredicate

object SqlPredicate {
  def backSubstituteAux[F[_]:Applicative](pred: SqlPredicate, sub: (TableName, SqlColumn) => F[SqlExpr]): F[SqlPredicate] =
    pred match {
      case SqlLt(l, r) => ^(SqlExpr.backSubstituteAux(l,sub),SqlExpr.backSubstituteAux(r,sub))(SqlLt(_,_))
      case SqlGt(l, r) => ^(SqlExpr.backSubstituteAux(l,sub),SqlExpr.backSubstituteAux(r,sub))(SqlGt(_,_))
      case SqlEq(l, r) => ^(SqlExpr.backSubstituteAux(l,sub),SqlExpr.backSubstituteAux(r,sub))(SqlEq(_,_))
      case SqlLte(l, r) => ^(SqlExpr.backSubstituteAux(l,sub),SqlExpr.backSubstituteAux(r,sub))(SqlLte(_,_))
      case SqlGte(l, r) => ^(SqlExpr.backSubstituteAux(l,sub),SqlExpr.backSubstituteAux(r,sub))(SqlGte(_,_))
      case SqlNot(p) => backSubstituteAux(p,sub) map (SqlNot(_))
      case SqlOr(ps@_*) => ps.toList.traverse[F,SqlPredicate](backSubstituteAux(_,sub)) map (SqlOr(_:_*))
      case SqlAnd(ps@_*) => ps.toList.traverse[F,SqlPredicate](backSubstituteAux(_,sub)) map (SqlAnd(_:_*))
      case SqlIsNull(e) => SqlExpr.backSubstituteAux(e,sub) map (SqlIsNull(_))
      case SqlFun(f, as) => (as.traverse[F,SqlExpr](SqlExpr.backSubstituteAux(_, sub))) map (SqlFun(f, _))
      case _ => pred.pure[F]
    }

  def fromLiteral(attrs: Map[SqlColumn, SqlExpr], lit: List[Record]): List[SqlPredicate] = lit match {
    case Nil => List()
    case _ =>
      val preds = lit map {
        r => SqlAnd(r.toList.map{
          case (c,pe) => SqlEq(attrs(c), SqlExpr.compileLiteral(pe))
        } :_*)
      }
      List(SqlOr(preds:_*))
  }
}

sealed abstract class SqlExpr {
  import scalaz.std.iterable._

  def emitSql(implicit emitter: SqlEmitter): RawSql = this match {
    case ColumnSqlExpr(table,column) => emitter.emitQualifiedColumnName(table, column)
    case BinSqlExpr(op, e1, e2) => raw("(") |+| e1.emitSql(emitter) |+| ") " |+| op |+| " (" |+| e2.emitSql(emitter) |+| ")"
    case PrefixSqlExpr(op, e1) => raw(op) |+| " (" |+| e1.emitSql(emitter) |+| ")"
    case PostfixSqlExpr(e1, op) => e1.emitSql(emitter) |+| " " |+| op
    case FunSqlExpr(fn, args) => raw(fn) |+| "(" |+| args.map(_.emitSql(emitter)).toIterable.rawMkString(", ") |+| ")"
    case IntervalExpr(n, u) => emitter.emitInterval(n, u)
    case LitSqlExpr(lit) => lit.emitSql(emitter)
    case CaseSqlExpr(clauses, otherwise) =>
      (raw("(case ") |+| clauses.map{case (t, c) =>
        raw("when ") |+| t.emitSql(emitter) |+| raw(" then ") |+| c.emitSql(emitter)}
       .rawMkString(" ")
       |+| raw(" else ") |+| otherwise.emitSql(emitter) |+| raw(" end)"))
    case ParensSqlExpr(e1) => raw("(") |+| e1.emitSql(emitter) |+| ")"
    case OverSqlExpr(e1, over) => emitter.emitOver(e1, over)
    case Verbatim(s) => s
    case CastSqlExpr(e, ty, nullIfFail, from) => emitter.emitCast(e, from, ty, nullIfFail)
  }

  @annotation.tailrec
  final def deparenthesize: SqlExpr = this match {
    case ParensSqlExpr(e) => e.deparenthesize
    case e => e
  }

  final def isConstant: Boolean = this match {
    case l : LitSqlExpr => true
    case IntervalExpr(e, _) => e.isConstant
    case ParensSqlExpr(e) => e.isConstant
    case CastSqlExpr(e,_,_,_) => e.isConstant
    case BinSqlExpr(_, e1, e2) => e1.isConstant && e2.isConstant
    case PrefixSqlExpr(_, e) => e.isConstant
    case PostfixSqlExpr(e, _) => e.isConstant
    case FunSqlExpr(_, args) => args.forall(_.isConstant)
    case v : Verbatim => false
    case o : OverSqlExpr => false
    case c : CaseSqlExpr => false
    case c : ColumnSqlExpr => false
  }
}

case class SqlOver(
  partition: List[SqlExpr],
  order: List[(SqlExpr, SqlOrder)],
  frameBegin: Option[Int],
  frameEnd: Option[Int]
)


case class ColumnSqlExpr(table: TableName, column: SqlColumn) extends SqlExpr
case class BinSqlExpr(f: String, a: SqlExpr, b: SqlExpr) extends SqlExpr
case class PrefixSqlExpr(f: String, arg: SqlExpr) extends SqlExpr
case class PostfixSqlExpr(arg: SqlExpr, f: String) extends SqlExpr
case class FunSqlExpr(f: String, args: List[SqlExpr]) extends SqlExpr
case class IntervalExpr(n: SqlExpr, units: TimeUnit) extends SqlExpr
case class LitSqlExpr(get: SqlLiteral) extends SqlExpr
case class CaseSqlExpr(clauses: NonEmptyList[(SqlPredicate, SqlExpr)],
                       otherwise: SqlExpr) extends SqlExpr
case class ParensSqlExpr(get: SqlExpr) extends SqlExpr
case class OverSqlExpr(e: SqlExpr, over: SqlOver) extends SqlExpr
/** `e` cast to `ty`; `from` is `e`'s type when the scanner could infer it
  * (`Op.guessType`), which a dialect whose storage classes do not match the
  * primitive types (SQLite's dates) needs to choose the conversion. */
case class CastSqlExpr(e: SqlExpr, ty: PrimT, nullIfFail: Boolean, from: Option[PrimT] = None) extends SqlExpr
case class Verbatim(sql: String) extends SqlExpr

object SqlExpr {
  def columns(h: Header, rv: TableName) = h.map(x => (x._1, ColumnSqlExpr(rv, x._1)))
  def columns(h: List[String], rv: TableName) = h.map(x => (x, ColumnSqlExpr(rv, x))).toMap

  def compileLiteral(e: PrimExpr): LitSqlExpr = e match {
    case StringExpr(_,s) => LitSqlExpr(SqlString(s))
    case ByteExpr(_,b) => LitSqlExpr(SqlByte(b))
    case ShortExpr(_,s) => LitSqlExpr(SqlShort(s))
    case IntExpr(_,i) => LitSqlExpr(SqlLong(i))
    case LongExpr(_,l) => LitSqlExpr(SqlLong(l))
    case DoubleExpr(_,d) => LitSqlExpr(SqlDouble(d))
    case DateExpr(_,d) => LitSqlExpr(SqlDate(d))
    case BooleanExpr(_,b) => LitSqlExpr(SqlBool(b))
    case UuidExpr(_,u) => LitSqlExpr(SqlUuid(u))
    case TimestampExpr(_,t) => LitSqlExpr(SqlTimestamp(t))
    case NullExpr(t) => LitSqlExpr(SqlNullOf(t))
  }

  def backSubstitute(expr: SqlExpr, sub: (TableName, SqlColumn) => SqlExpr): SqlExpr =
    backSubstituteAux[Id](expr, sub)

  def backSubstituteSingle(expr: SqlExpr, sub: (TableName, SqlColumn) => SqlExpr): Option[SqlExpr] = {
    def msub(t:TableName,s:SqlColumn) = sub(t, s) match {
      case s : ColumnSqlExpr => Some(s)
      case _ => None
    }
    backSubstituteAux[Option](expr, msub)
  }

  def backSubstituteAux[F[_]:Applicative](expr: SqlExpr, sub: (TableName, SqlColumn) => F[SqlExpr]): F[SqlExpr] = {
    expr match {
      case ColumnSqlExpr(t, c) => sub(t, c)
      case BinSqlExpr(f, a, b) =>
        ^(backSubstituteAux(a, sub), backSubstituteAux(b, sub))(BinSqlExpr(f,_,_))
      case PrefixSqlExpr(f, a) =>
        backSubstituteAux(a, sub) map (PrefixSqlExpr(f, _))
      case PostfixSqlExpr(a, f) => backSubstituteAux(a, sub) map (PostfixSqlExpr(_, f))
      case FunSqlExpr(f, as) => (as.traverse[F,SqlExpr](backSubstituteAux(_, sub))) map (FunSqlExpr(f, _))
      case CaseSqlExpr(cs, e) =>
        val ncs = cs.traverse[F,(SqlPredicate,SqlExpr)] {
          case (p, e) => ^(SqlPredicate.backSubstituteAux(p, sub), backSubstituteAux(e, sub))((_,_))
        }
        ^(ncs, backSubstituteAux(e, sub))(CaseSqlExpr(_,_))
      case ParensSqlExpr(e) => backSubstituteAux(e, sub) map (ParensSqlExpr(_))
      case OverSqlExpr(e, over) =>
        ^(backSubstituteAux(e, sub), backSubstituteOver(over, sub))(OverSqlExpr(_,_))
      case _ => expr.pure[F]
    }
  }

  private def backSubstituteOver[F[_]:Applicative](
    over: SqlOver,
    sub: (TableName, SqlColumn) => F[SqlExpr]): F[SqlOver] = over match {
      case SqlOver(part, ord, begin, end) =>
        (part.traverse(backSubstituteAux(_, sub)) |@|
         ord.traverse {
           case (e, o) => backSubstituteAux(e, sub) map ((_, o))
         })(SqlOver(_, _, begin, end))
  }
}

sealed abstract class SqlLiteral {
  def emitSql(implicit emitter: SqlEmitter): RawSql = this match {
    case SqlString(s) => emitter.emitString(s)
    case SqlBool(b) => emitter.emitBoolean(b)
    case SqlInt(i) => i.toString
    case SqlLong(l) => l.toString
    case SqlDouble(d) => emitter.emitDouble(d)
    case SqlByte(b) => b.toString
    case SqlShort(s) => s.toString
    case SqlDate(d) => emitter.emitDate(d)
    case SqlUuid(u) => emitter.emitUuid(u)
    case SqlTimestamp(t) => emitter.emitTimestamp(t)
    case SqlNull => emitter.emitNull
    case SqlNullOf(t) => emitter.emitTypedNull(t)
  }
}
case class SqlString(get: String) extends SqlLiteral
case class SqlBool(get: Boolean) extends SqlLiteral
case class SqlByte(get: Byte) extends SqlLiteral
case class SqlShort(get: Short) extends SqlLiteral
case class SqlInt(get: Int) extends SqlLiteral
case class SqlLong(get: Long) extends SqlLiteral
case class SqlDouble(get: Double) extends SqlLiteral
case class SqlDate(get: Date) extends SqlLiteral
case class SqlUuid(get: UUID) extends SqlLiteral
case class SqlTimestamp(get: java.sql.Timestamp) extends SqlLiteral
case object SqlNull extends SqlLiteral
/** A NULL that knows its type: `cast(NULL as <type>)`.  An untyped NULL in a
  * VALUES row or an empty relation is typed by the dialect's guess (SQL
  * Server: int), and an aggregate over it is then refused (SQL audit E22). */
case class SqlNullOf(t: PrimT) extends SqlLiteral

