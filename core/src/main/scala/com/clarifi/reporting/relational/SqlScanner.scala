package com.clarifi.reporting
package relational

import java.sql.SQLException

import com.clarifi.reporting.ReportingUtils.simplifyPredicate
import com.clarifi.reporting.backends.DB._
import com.clarifi.reporting.backends._
import com.clarifi.reporting.sql.SqlExpr._
import com.clarifi.reporting.sql._
import com.clarifi.reporting.util.PartitionedSet
import scalaz.Coproduct._
import scalaz.Id._
import scalaz._
import scalaz.std.anyVal._
import scalaz.std.function._
import scalaz.std.indexedSeq.{toNel => _, _}
import scalaz.std.list._
import scalaz.std.map._
import scalaz.std.option._
import scalaz.std.string._
import scalaz.std.vector.{toNel => _, _}
import scalaz.syntax.monad._
import scalaz.syntax.traverse.{ToFunctorOps => _, _}
import com.clarifi.machines.Plan.{await, awaits, emit}
import com.clarifi.machines.Tee.{left, right}
import com.clarifi.machines._
import com.clarifi.reporting.util.PimpedLogger._
import org.apache.log4j.Logger
import scalaparsers.Supply

// important for instance resolution.
import scala.collection.immutable.IndexedSeq
import scala.collection.immutable.SortedSet
import scala.collection.mutable.HashSet

//TODO: switch to a dumber supply that is onyl locally unique instead of globally so.
//TODO: also swap temp tables to be locally fresh instead of guids

class SqlScanner(sms: SMEnv[DB])(implicit emitter: SqlEmitter) extends Scanner[DB] {
  case class SqlPrg(prg: List[SqlStatement],
                    notes: List[String],
                    q: DistinctiveQuery,
                    refl: Reflexivity[ColumnName])

  case class MemPrg(h: Header,
                    prg: List[SqlStatement],
                    p:  OrderedProcedure[DB, Record],
                    refl: Reflexivity[ColumnName])

  /** One per scan: the temp table a CLOSED let-bound relation (`LetR` whose
    * `ext` mentions no bound variable, e.g. `materialize r`) was compiled
    * into, keyed by the relation value and its primary key.  Every reference
    * to such a relation used to mint its own temp table and fill it again
    * (`Algebra.Helpers.closure` at depth 4: 40 temp tables for 4 distinct
    * relations, audit O-25, L-21); now the same statements are reused, so
    * `sequenceSql`'s `distinct` runs them once.  Relations mentioning a bound
    * variable are compiled per visit as before, since their meaning depends on
    * the scope. */
  final class LetCache {
    private[this] val tables =
      new scala.collection.mutable.HashMap[(String, List[String]), (Header, Reflexivity[ColumnName], List[SqlStatement], TableName)]
    def getOrElseUpdate(ext: Any, pk: List[String],
                        make: => (Header, Reflexivity[ColumnName], List[SqlStatement], TableName)) =
      tables.getOrElseUpdate((LetCache.key(ext), pk), make)
    def size: Int = tables.size
  }

  object LetCache {
    /** A SHA-1 of an EXACT structural rendering of `x`: every `PrimExpr` with
      * its type, nullability and exact value (`PrimExpr` equality is
      * case-insensitive for strings and makes NULL equal to NULL, so keying by
      * `==` would let `"a"` and `"A"` share one temp table and SQLite read the
      * wrong case), every literal's rows (`Literal` is not a case class and
      * `SmallLit` prints values without their types), and otherwise the case
      * class structure.  A quote's identity object renders by identity. */
    def key(x: Any): String = {
      val md = java.security.MessageDigest.getInstance("SHA")
      def put(s: String): Unit = { md.update(s.getBytes("UTF-8")); md.update(0.toByte) }
      def go(v: Any): Unit = v match {
        case p: PrimExpr =>
          put(p.typ.toString); put(if (p.nullable) "?" else "!")
          put(if (p.isNull) "NULL" else "=" + (p.value match {
            case d: java.util.Date => d.getTime.toString // exact millis, not the zone-dependent print
            case v => v.toString
          }))
        case l: Literal => put("Literal("); l.seq.foreach(go); put(")")
        case m: scala.collection.Map[_, _] =>
          put("Map("); m.toList.sortBy(_._1.toString).foreach { case (k, w) => go(k); put("->"); go(w) }; put(")")
        case s: scala.collection.Set[_] => put("Set("); s.toList.map(e => key(e)).sorted.foreach(put); put(")")
        case o: Option[_] => put("Option("); o.foreach(go); put(")")
        case i: Iterable[_] => put("Seq("); i.foreach(go); put(")")
        case p: Product => put(p.productPrefix + "("); p.productIterator.foreach(go); put(")")
        case null => put("null")
        case other => put(other.toString)
      }
      go(x)
      md.digest.map("%02x" format _).mkString
    }
  }

  private[this] def logger = Logger getLogger this.getClass

  import AggFunc._

  private[this] def fillTable(table: TableName, header: Header, from: SqlQuery, hints: TableHints = TableHints.empty
                             ): List[SqlStatement] = {
    val c = SqlCreate(table = table, header = header, hints = hints)
    List(c, SqlInsert(table, c.hints.sortColumns(header.keySet), from))
  }

  /** Compile an `op`, delegating column reference expression
    * compilation to `lookupColumn`.
    */
  def compileOp(op: Op, lookupColumn: String => SqlExpr)(implicit emitter: SqlEmitter): SqlExpr = {
    import Op._
    def compileBuiltin(b: Builtin) = b match {
      case Upper => "UPPER"
      case Lower => "LOWER"
      case Log => "LOG"
      case Log10 => "LOG10"
      case Exp => "EXP"
      case LogBase => "LOG"
      case Abs => "ABS"
      case Pow => "POWER"
      case Replace => "REPLACE"
    }

    def rec(op: Op): SqlExpr = op match {
      case OpLiteral(lit) => compileLiteral(lit)
      case ColumnValue(cn, _) => lookupColumn(cn)
      case Add(a, b) =>
        BinSqlExpr("+", rec(a), rec(b))
      case Sub(a, b) =>
        BinSqlExpr("-", rec(a), rec(b))
      case Mul(a, b) =>
        BinSqlExpr("*", rec(a), rec(b))
      case FloorDiv(a, b) =>
        emitter.emitIntegerDivision(rec(a), rec(b))
      case DoubleDiv(a, b) =>
        BinSqlExpr("/", rec(a), rec(b))
      case Concat(as) =>
        emitter.emitConcat(as.map(rec))
      // An `if` whose ALTERNATE is an `if` flattens into the same CASE:
      // `case when t then c when t2 then x else y end` falls through to
      // the inner tests exactly when `t` is false or unknown, as the nested
      // form does.  An `if` whose CONSEQUENT is an `if` used to be merged
      // as `case when not t then z when t2 ...`, which for an unknown `t`
      // (a NULL operand) skips the `not t` clause and answers from the inner
      // branches where the nested form answers `z`; it stays nested now
      // (SQL audit E15).
      case If(test, conseq, altern) => (rec(conseq), rec(altern)) match {
        case (cConseq, CaseSqlExpr(clauses, oth)) =>
          CaseSqlExpr((compilePredicate(test, lookupColumn),
                       cConseq) <:: clauses, oth)
        case (cConseq, cAltern) =>
          CaseSqlExpr(NonEmptyList((compilePredicate(test, lookupColumn),
                                    cConseq)),
                      ParensSqlExpr(cAltern))
      }
      case Coalesce(l, r) =>
        FunSqlExpr("coalesce", List(rec(l),rec(r)))
      case DateAdd(d, n, u) => emitter.emitDateAdd(rec(d), rec(n), u)
      case DateDiff(u, s, e) => emitter.emitDateDiff(u, rec(s), rec(e))
      case Funcall(name, db, ns, args, _) =>
        FunSqlExpr(emitter emitProcedureName (name, ns) run,
                   args map rec)
      case Windowed(agg, over) =>
        OverSqlExpr(compileWindowFunc(agg, lookupColumn), compileWindow(over, lookupColumn))
      case BuiltinCall(b,args) => FunSqlExpr(compileBuiltin(b), args.map(rec))
      case Cast(o, ty, nullIfFail) => CastSqlExpr(rec(o), ty, nullIfFail, o.guessType.toOption)
    }
    rec(op.simplify(Map()))
  }

  private def compileOrder(ord: SortOrder): SqlOrder =
    ord(SqlAsc, SqlDesc)

  private def compileWindow(over: Window, attrs: String => SqlExpr): SqlOver = over match {
    case Window(part, ord, frame) =>
      SqlOver(
        part.map(compileOp(_, attrs)),
        ord.map{ case (e, o) => (compileOp(e, attrs), compileOrder(o)) },
        frame.preceding,
        frame.following
      )
  }

  def compileAggFunc(f: AggFunc, attrs: String => SqlExpr): SqlExpr = f match {
    case Count => FunSqlExpr("COUNT", List(Verbatim("*")))
    case Sum(x) => FunSqlExpr("SUM", List(compileOp(x, attrs)))
    case Avg(x) => emitter.emitAvg(compileOp(x, attrs), x.guessType.toOption)
    case Min(x) => FunSqlExpr("MIN", List(compileOp(x, attrs)))
    case Max(x) => FunSqlExpr("MAX", List(compileOp(x, attrs)))
    case Stddev(x) => emitter.emitStddevPop(compileOp(x, attrs))
    case Variance(x) => emitter.emitVarPop(compileOp(x, attrs))
    case WMean(x,w) =>
      val cw = compileOp(w,attrs)
      val num = FunSqlExpr("SUM", List(BinSqlExpr("*", compileOp(x,attrs), cw)))
      val den = FunSqlExpr("SUM", List(cw))
      BinSqlExpr("/", num, den)
    case WHMean(x,w) =>
      val cw = compileOp(w,attrs)
      val num = FunSqlExpr("SUM", List(cw))
      val den = FunSqlExpr("SUM", List(BinSqlExpr("/", cw, compileOp(x,attrs))))
      BinSqlExpr("/", num, den)
  }

  def compileWindowFunc(f: WindowFunc, attrs: String => SqlExpr): SqlExpr = f match {
    case AggWindowFunc(agg) => compileAggFunc(agg, attrs)
    case Rank => FunSqlExpr("RANK", List())
    case DenseRank => FunSqlExpr("DENSE_RANK", List())
    case RowNumber => FunSqlExpr("ROW_NUMBER", List())
    case NTile(op) => FunSqlExpr("NTILE", List(compileOp(op, attrs)))
  }

  /** Compile a `predicate`, delegating column reference expression
    * compilation to `lookupColumn`.
    */
  def compilePredicate(predicate: Predicate,
                       lookupColumn: String => SqlExpr)(
                       implicit emitter: SqlEmitter): SqlPredicate = {
    def subop(op: Op) = compileOp(op, lookupColumn)
    // `Relation.Predicate`'s `a <= b` is `a < b || a == b`; with the same
    // two operands on both sides it is one comparison (SQL audit E14).
    def or(l: SqlPredicate, r: SqlPredicate): SqlPredicate = (l, r) match {
      case (SqlLt(a, b), SqlEq(c, d)) if (a == c && b == d) || (a == d && b == c) => SqlLte(a, b)
      case (SqlEq(c, d), SqlLt(a, b)) if (a == c && b == d) || (a == d && b == c) => SqlLte(a, b)
      case (SqlGt(a, b), SqlEq(c, d)) if (a == c && b == d) || (a == d && b == c) => SqlGte(a, b)
      case (SqlEq(c, d), SqlGt(a, b)) if (a == c && b == d) || (a == d && b == c) => SqlGte(a, b)
      case _ => SqlOr(l, r)
    }
    predicate.apply[SqlPredicate](
      atom = b => SqlTruth(b),
      lt = (s1, s2) => SqlLt(subop(s1), subop(s2)),
      gt = (s1, s2) => SqlGt(subop(s1), subop(s2)),
      eq = (s1, s2) => SqlEq(subop(s1), subop(s2)),
      not = e => SqlNot(e),
      or = or,
      and = SqlAnd(_, _),
      isNull = e => SqlIsNull(subop(e)),
      funtest = (name, db, ns, args) => SqlFun(emitter emitProcedureName (name, ns) run, args map subop)
    )
  }


  val exec = new SqlExecution()
  import exec._

  private[this]
  def explainSQLException(e: SQLException): String =
    s"ErrorCode=`${e.getErrorCode}' SQLState=`${e.getSQLState}' class=`${e.getClass}' msg=`${e.getMessage}'"

  private[this]
  def transaction[A](act: DB[A]) =
    if (emitter.isTransactional) DB.transaction(act)
    else act

  /** Execute `p` statements, returning the list of `TableName`s that were
    * created.
    */
  def sequenceSql(p : List[SqlStatement])(implicit memoLookup : HashSet[TableName]): DB[List[TableName]] = p.distinct.traverse {
    case SqlLoad(tn, h, pc) => traced("load", Some(tn))(bulkLoad(h, tn, pc)) as List()
    case SqlCreateIfNotExists(tn,pre,create,stats) =>
      if(memoLookup.contains(tn))
          List().point[DB]
          else {
            memoLookup += tn
            val tecol = "tableExists"
            val (sql, errorMeansExists) = emitter.checkExists(tn, tecol)
            logger ltrace ("Executing sql: " + sql.run)
            transaction(traced("memo", Some(tn), (b: Boolean) => Some(!b))(withResultSet(sql, rs => {
              rs.next() && (rs.getObject(tecol) ne null)
            }.point[DB])).flatMap(b =>
              if (!b) ^(sequenceSql(pre),
                        catchException(sequenceSql(List(create))).flatMap{
                          case -\/(e: SQLException) if errorMeansExists(e) =>
                            logger ltrace s"SQL memocache race caught, dropped: ${explainSQLException(e)}"
                          List().point[DB]
                          case -\/(e: SQLException) =>
                            logger error "SQL error in memocache: ${explainSQLException(e)}"
                          throw e
                          case -\/(e) => throw e
                          case \/-(u) => sequenceSql(stats)
                        })(_ ++ _)
              else List().point[DB]))
          }

    case x =>
      val sql = x.emitSql(emitter)
      val sStart = System.currentTimeMillis
      logger ltrace ("Executing sql: " + sql.run)
      val kind = x match {
        case SqlCreate(TableName(_, _, TableName.Temporary), _, _, _) => "temp"
        case _: SqlCreate                                            => "create"
        case _                                                       => "statement"
      }
      val table = x match { case sc: SqlCreate => Some(sc.table); case _ => None }
      traced(kind, table)(DB.executeUpdate(sql)) as {
        val sDelta = System.currentTimeMillis - sStart
        logger ltrace (s"Finished executing statement -- took $sDelta ms")
        x match {case sc: SqlCreate => List(sc.table)
                 case _ => List()}
      }
  }.map{_.flatten}

  /** S2b: `act` timed when it RUNS (not when the `traverse` builds it) and
    * recorded on this thread's `RenderTrace` as one setup statement; a
    * no-op test and the action itself when no trace is installed.  The
    * statement is recorded (with `error`) when it throws, too. */
  private[this]
  def traced[A](kind: String, tn: Option[TableName], created: A => Option[Boolean] = (_: A) => None)
               (act: DB[A]): DB[A] = c => {
    val tr = RenderTrace.current
    if (!tr.on) act(c)
    else {
      val t0 = System.nanoTime
      val name = tn.map(t => (t.schema :+ t.name).mkString("."))
      val a = try act(c) catch {
        case e: Throwable => tr.statement(kind, name, None, System.nanoTime - t0, error = true); throw e
      }
      tr.statement(kind, name, created(a), System.nanoTime - t0)
      a
    }
  }

  private[this]
  def cleanTempTables(ts: List[TableName]): DB[Unit] =
    emitter.emitDropTempTable
      .map{dtt => ts.traverse_ {
             case tn@TableName(_, _, TableName.Temporary) =>
               val sql = dtt(tn)
               logger ltrace ("Executing sql: " + sql.run)
               traced("drop", Some(tn))(DB.executeUpdate(sql))
             case _ => ().point[DB]
           }}
      .getOrElse(().point[DB])

  def scanMem[A:Monoid](m: Mem[Nothing, Nothing],
                        f: Process[Record, A],
                        order: List[(String, SortOrder)] = List()): DB[A] = {
    implicit val sup = Supply.create
    implicit val memoLookup = new HashSet[TableName]()
    implicit val scopeBuilder = List()
    implicit val letCache = new LetCache
    val tr = RenderTrace.current
    val c0 = if (tr.on) System.nanoTime else 0L
    compileMem(Optimizer.optimize(m), (x:Nothing) => x, (x: Nothing) => x) match {
      case MemPrg(h, p, q, rx) =>
        if (tr.on) tr.sqlEmitted(System.nanoTime - c0)
        // `ensure`: the temp tables are dropped when the scan FAILS too; the
        // drop only ran after a successful scan (audit L-11, L-12).
        sequenceSql(p).flatMap(ts =>
          DB.ensure(q(order) map (_ andThen f execute), cleanTempTables(ts)))
    }
  }

  def scanRel[A:Monoid](m: Relation[Nothing, Nothing],
                        f: Process[Record, A],
                        order: List[(String, SortOrder)] = List()): DB[A] = {
    implicit val sup = Supply.create
    implicit val memoLookup = new HashSet[TableName]()
    implicit val scopeBuilder = List()
    implicit val letCache = new LetCache
    val tr = RenderTrace.current
    val c0 = if (tr.on) System.nanoTime else 0L
    compileRel(Optimizer.optimize(m), (x:Nothing) => x, (x: Nothing) => x) match {
      case SqlPrg(p, ns, q, rx) =>
        if (tr.on) tr.sqlEmitted(System.nanoTime - c0)
        sequenceSql(p).flatMap(ts =>
          DB.ensure(scanAndUniq(q, order, ns) map (_ andThen f execute), cleanTempTables(ts)))
    }
  }

  override def dumpRel(m: Relation[Nothing, Nothing],
                       order: List[(String, SortOrder)] = List()): String = {
    implicit val sup = Supply.create
    implicit val memoLookup = new HashSet[TableName]()
    implicit val scopeBuilder = List()
    implicit val letCache = new LetCache
    compileRel(Optimizer.optimize(m), (x: Nothing) => x, (x: Nothing) => x) match {
      case SqlPrg(prg, notes, dq, _) =>
        val stmts = prg.distinct.map(x => x.emitSql(emitter).run)
        val query = dq.q(emitter.distinctEagerly) match {
          case (d, q) =>
            orderQuery(dq.h,q, order).emitSql(emitter).run
        }
        ((stmts :+ query) ++ notes.map("-- " + _)).mkString("\n")
    }
  }

  def scanExt[A:Monoid](m: Ext[Nothing, Nothing],
                        f: Process[Record, A],
                        order: List[(String, SortOrder)] = List()): DB[A] = m match {
      case ExtRel(r, db) => scanRel(r, f, order)
      case ExtMem(mem) => scanMem(mem, f, order)
      case ExtSM(sm) => sms(sm)._1.apply(order).map(_.andThen(f).execute)
    }

  def guidName = "t" + sguid
  def freshName(implicit sup: Supply) = "t" + sup.fresh

  def orderQuery(h: Header, sql: SqlQuery.Nestable with SqlQuery.Scannable, order: List[(String, SortOrder)])(implicit sup: Supply): SqlQuery.Scannable =
    if (order.isEmpty) {
      sql
    } else {
      SqlQuery.orderBy(DistinctiveQuery.asOrderable(h, sql),
                       order.map { case (col, ord) =>
                         (col,
                          ord(SqlAsc, SqlDesc))
                       }
                      )
    }

  import SortOrder._
  import record.RecordMap

  private[this]
  def scanAndUniq(dq: DistinctiveQuery,
                  order: List[(String, SortOrder)],
                  notes: List[String])(implicit sup: Supply): DB[Procedure[Id, Record]] =
    dq.q(emitter.distinctEagerly) match {
      case (d, q) =>
        if (d) scanQuery(orderQuery(dq.h, q, order), dq.h, notes) // already distinct
        else {
          val unsortedCols = dq.h.keySet -- order.map(_._1)
          val totalOrder = order ++ unsortedCols.toList.map(c => (c, Asc))
          scanQuery(orderQuery(dq.h, q, totalOrder), dq.h, notes) map (_ andThen uniqSorted)
        }
    }

  def compileJoinMode(mode: JoinMode): SqlJoinOp = mode match {
    case JoinMode.Inner => SqlJoinInner
    case JoinMode.Left  => SqlJoinLeft
    case JoinMode.Right => SqlJoinRight
    case JoinMode.Full  => SqlJoinFull
  }

  def compileMem[M,R](m: Mem[R, M], smv: M => MemPrg, srv: R => SqlPrg)(implicit sup: Supply, memoLookup: HashSet[TableName], scopeBuilder : List[() => String], letCache: LetCache): MemPrg =
    m match {
      case VarM(v) => smv(v)
      case LetM(ext, expr) =>
        val p = compileMem(MemoMem(EmbedMem(ext)) , smv, srv )
        val MemPrg(h, ps, pop, rx) = p
        val ep = compileMem(expr, (v: MLevel[R, M]) => v match {
            case MTop => MemPrg(h, List(), pop, rx)
            case MPop(mex) => compileMem(mex, smv, srv)
          }, srv)
        ep copy (prg = ps ++ ep.prg)
      case mm@MemoMem(e) => {
          val MemPrg(h, sqls, p, rx) = compileMem(e, smv, srv)
          MemPrg(h, sqls, memoProc(p, mm), rx)
        }
      case EmbedMem(ExtMem(e)) => compileMem(e, smv, srv)
      case EmbedMem(ExtRel(e, _)) => // TODO: Ditto
        val SqlPrg(ps, ns, q, rx) = compileRel(e, smv, srv)
        MemPrg(q.h, ps, o => scanAndUniq(q, o, ns), rx)
      case EmbedMem(ExtSM(e)) =>
        val (p, h, rx) = sms(e)
        MemPrg(h, List(), p, rx)
      case CombineM(e, attr, op) =>
        val MemPrg(h, ps, q, rx) = compileMem(e, smv, srv)
        val needUniq = h.contains(attr.name) // this is over-aggressive
        MemPrg(h + (attr.name -> attr.t), ps, o =>
          if (!o.toMap.contains(attr.name))
            q(o).map(_.map(t => t + (attr.name -> op.eval(t))))
          else {
            val oo = o takeWhile { case (n, _) => n != attr.name }
            q(oo) map { proc =>
              val nproc = proc map (t => t + (attr.name -> op.eval(t))) andThen sorting(oo, o)
              if (needUniq) nproc andThen uniq(o.map(_._1).toSet) else nproc
            }
          }, rx combineAll(Map(attr.name -> op), { case x => x }, x => x))
      case AggregateM(e, attr, op) =>
        def mkRecord(n: ColumnName)(p: PrimExpr) = RecordMap(n -> p)
        def aggregateOrderedProc(q: OrderedProcedure[DB, Record])(l: List[(String, SortOrder)]): DB[Procedure[scalaz.Id.Id, Record]] = {
          val qq: DB[Procedure[scalaz.Id.Id, Record]] = q(List())
          qq map ((x: Procedure[scalaz.Id.Id, Record]) => x andThen reduceProcess(op, attr.t).outmap( mkRecord(attr.name) ))
        }
        
        val MemPrg(h, ps, q, rx) = compileMem(e, smv, srv)
        MemPrg(Map(attr.name -> attr.t),
               ps,
               aggregateOrderedProc(q),
               ForallTups(Map(attr.name -> None), PartitionedSet.zero))
      case LimitM(m, start, stop, order) =>
        val MemPrg(h, ps, q, rx) = compileMem(m, smv, srv)
        // 1-based and INCLUSIVE, as `Limit`, Sort.e and the emitters are
        // (audit L-7, S-11, O-8): (Just 2, Just 3) is the second and third
        // row, (Just 1, Just 1) the first; it used to drop `start` rows and
        // take `stop - start`.  With no order it sorts by every column, as the
        // SQL side does, and the rows are re-sorted to the order the consumer
        // asked for, which it used to ignore (audit L-9).
        val fromn = start.getOrElse(1)
        val actualOrder = if (!order.isEmpty) order
                          else h.map { case (k, _) => (k, SortOrder.Asc) }.toList
        val drop = if (fromn > 1) Some(Process.dropping[Record](fromn - 1)) else None
        val take = stop.map(t => Process.taking[Record](math.max(0, t - fromn + 1)))
        MemPrg( h,
                ps,
                o => q(actualOrder) map {proc => val dropped = drop.map( proc andThen _ ).getOrElse(proc)
                                                 val taken = take.map( dropped andThen _ ).getOrElse(dropped)
                                                 taken andThen sorting(actualOrder, o)
                                        },
                rx
              )

      case FilterM(m, p) =>
        val MemPrg(h, ps, q, rx) = compileMem(m, smv, srv)
          MemPrg(h, ps,
                 o => q(o) map (_ andThen Process.filtered(Predicates.toFn(simplifyPredicate(p, rx)))),
                 rx && Predicates.constancies(p))
      // TODO: Spec out SM joins
      case MergeOuterJoin(m1, m2) =>
        val r1 = compileMem(m1, smv, srv)
        val r2 = compileMem(m2, smv, srv)
        val MemPrg(h1, p1, q1, rx1) = r1
        val MemPrg(h2, p2, q2, rx2) = r2
        val jk = h1.keySet intersect h2.keySet
        MemPrg(h1 ++ h2, p1 ++ p2, o => {
          val prefix = o takeWhile (x => jk contains x._1)
          val preo = prefix ++ jk.view.filterNot(prefix.toMap.contains).map(_ -> Asc)
          // A join key holding a NULL never matches (decision D1, item C21):
          // two such keys that the record order calls EQUAL are answered LT,
          // so the merge emits the left row unmatched and, on the next step,
          // the right one; the streams stay sorted under either answer.
          val ord0: Order[Record] = recordOrd(preo)
          val ord: Order[Record] = Order.order((a: Record, b: Record) => ord0.order(a, b) match {
            case scalaz.Ordering.EQ if nullKeyed(jk)(a) => scalaz.Ordering.LT
            case o => o
          })
          val merged = ^(q1(preo), q2(preo))(
            (q1p, q2p) => q1p.tee(q2p)(Tee.mergeOuterJoin((r: Record) => (r filterKeys jk).toMap,
                                                          (r: Record) => (r filterKeys jk).toMap
                                                          )(ord)).map {
            case This(a) => RecordMap(h2 map (kv => kv._1 -> NullExpr(kv._2))) ++ a
            case That(b) => RecordMap(h1 map (kv => kv._1 -> NullExpr(kv._2))) ++ b
            case Both(a, b) => a ++ b
          })
          if (prefix == o) merged else merged map (_ andThen sorting(prefix, o))
        }, rx1 && rx2)
      case UnionM(m1, m2) => compileMerge(m1, m2, smv, srv, mergeTee)
      case DifferenceM(m1, m2) => compileMerge(m1, m2, smv, srv, diffTee)
      case HashInnerJoin(m1, m2) =>
        val r1 = compileMem(m1, smv, srv)
        val r2 = compileMem(m2, smv, srv)
        val MemPrg(h1, p1, q1, rx1) = r1
        val MemPrg(h2, p2, q2, rx2) = r2
        val jk = h1.keySet intersect h2.keySet
        MemPrg(h1 ++ h2,
               p1 ++ p2,
               o => {
                 val os = o.toMap.keySet
                 val o1 = os -- h1.keySet
                 val o2 = os -- h2.keySet
                 val prefix1 = o takeWhile (x => h1.keySet(x._1))
                 val prefix2 = o takeWhile (x => h2.keySet(x._1))
                 if (o1.isEmpty)
                   hashJoin(q2(List()), q1(o), jk)
                 else if (o2.isEmpty)
                   hashJoin(q1(List()), q2(o), jk)
                 else if (prefix1.length > prefix2.length)
                   hashJoin(q2(List()), q1(prefix1), jk) map (_ andThen sorting(prefix1, o))
                 else
                   hashJoin(q1(List()), q2(prefix2), jk) map (_ andThen sorting(prefix2, o) )},
               rx1 && rx2)
      case HashLeftJoin(inner, outer) =>
        val MemPrg(hin,  pin,  qin,  rxin)  = compileMem(inner, smv, srv)
        val MemPrg(hout, pout, qout, rxout) = compileMem(outer, smv, srv)
        val jk = hin.keySet intersect hout.keySet
        val nulls : Record = hout collect {
          case (col, ty) if !(jk contains col) => col -> NullExpr(ty)
        }
        MemPrg(hin ++ hout,
               pin ++ pout,
               o => {
                 val pfx = o takeWhile(x => hin.keySet(x._1))
                 if (pfx.length == o.length) // no sorting needed
                   leftHashJoin(qin(o), qout(List()), jk, nulls)
                 else
                   leftHashJoin(qin(pfx), qout(List()), jk, nulls) map (_ andThen sorting(pfx, o))
               },
               rxin && rxout)
      case ProcessM(f, m) =>
        val MemPrg(h, p, q, r) = compileMem(m, smv, srv)
        MemPrg(f.outputType(h), p, q andThen (_ map (_ andThen f.compile)), r)
      case AccumulateM(parentIdCol, nodeIdCol, expr, l, t) =>
        val MemPrg(ht,pt,qt,rt) = compileMem(t, smv, srv)
        val MemPrg(hl,pl,ql,rl) = compileMem(l, smv, srv)
        val accumProc: OrderedProcedure[DB,Record] = {
          (ord: List[(String, SortOrder)]) => (db: java.sql.Connection) =>
            // read both the tree and leaves into memory because working on this in a streaming
            // fashion is difficult
            var leaves = Map[PrimExpr, Record]() // map from nid to (|..nid..v|)
            var tree   = Map[PrimExpr, Record]() // map from nid to (|..nid..pid..k|)
            qt(List())(db).foreach( rec => tree = tree + (rec(nodeIdCol.name) -> rec) )
            ql(List())(db).foreach( rec => leaves = leaves + (rec(nodeIdCol.name) -> rec) )

            // map from nid to all of the leaves in its subtree
            // for example, the root node will have every list
            var descendantLeaves: Map[PrimExpr, Vector[Record]] = Map().withDefaultValue(Vector())
            // for each leaf, recursively add itself to its parent, grandparent, (great^n)grandparent's list
            def insertIntoDescendantLeaves(parentId: PrimExpr, leaf: Record): Unit = {
              // Make sure the leaf's parent exists in the tree, because a leaf could be an orphan
              // and it doesn't make sense to add orphans to descendantLeaves.  A NULL id
              // matches no node (decision D1, item C21): `NullExpr == NullExpr` in memory.
              if (!parentId.isNull) tree.get(parentId) foreach { parent =>
                descendantLeaves = descendantLeaves + (parentId -> (descendantLeaves(parentId) :+ leaf))
                val grandParentId = parent(parentIdCol.name)
                if( !grandParentId.isNull && tree.contains(grandParentId) ) // Are we at the root node yet?
                  insertIntoDescendantLeaves(grandParentId, leaf)
              }
            }
            leaves.foreach { case (nid,leaf) =>
              insertIntoDescendantLeaves( leaf(nodeIdCol.name), leaf )
            }
            descendantLeaves.view.map { case (nid, leafVec) =>
              val leafRec = Literal( leafVec.head, leafVec.tail) 
              val subquery = Mem.instantiate(leafRec, expr)
              val MemPrg(sh, sp, sq, sr) = compileMem(subquery, smv, srv)
              if (!sp.isEmpty)
                sys.error("subqueries of groupBy cannot 'let' new temp tables: " + subquery)
              else {
                val nodeTup = (nodeIdCol.name -> nid)
                sq(List())(db).map(_ + nodeTup)
              }
            }.foldLeft(Mem.zeroProcedure[Record])((p1,p2) => Mem.append(p1,p2)).
              andThen(sorting(List(), ord) andThen uniq(ord.map(_._1).toSet))
        }
        implicit val err: Typer.Errs[Option] = new Typer.Errs[Option] {
          def apply(s: String, msgs: String*): Option[Nothing] = None
        }
        val hdr = Typer.accumulateType[Option](
          parentIdCol.toHeader, nodeIdCol.toHeader,
          v => Typer.memTyper(Mem.instantiate(EmptyRel(v), expr).substPrg(srv andThen (_.q.h), smv andThen (_.h))).toOption,
          Typer.memTyper(l.substPrg(srv andThen (_.q.h),smv andThen (_.h))).toOption.get).get
        MemPrg(hdr, pt ++ pl, accumProc, rt.filterKeys((k:String) => k == nodeIdCol.name))
      case GroupByM(m, k, expr) =>
        def toOp(a: Attribute) = Op.ColumnValue(a.name, a.t)
        val MemPrg(h, p, q, r) = compileMem(m, smv, srv)
        val knames = k.map(_.name).toSet
        // The body is compiled ONCE, against a placeholder that reads the
        // current group's rows when its procedure is made; it was
        // instantiated with each group's literal and compiled again per group
        // (audit S-22).  A body holding a `letM`/`MemoMem` keeps the old way:
        // its memo lives on the node and would hold the FIRST group's rows.
        // Within a group the key columns are constant (value unknown), on top
        // of what `m` guarantees for every row.
        val groupRows = new java.util.concurrent.atomic.AtomicReference[Literal]
        val groupRx: Reflexivity[ColumnName] =
          r && ForallTups(knames.map(n => (n, None: Option[PrimExpr])).toMap, PartitionedSet.zero)
        val once: Option[OrderedProcedure[DB, Record]] =
          if (Mem.hasMemo(expr)) None
          else {
            val MemPrg(_, sp, sq, _) = compileMem(expr, (v: MLevel[R, M]) => v match {
                case MTop => MemPrg(h, List(), so => literalProcedure(groupRows.get, so).point[DB], groupRx)
                case MPop(mex) => compileMem(mex, smv, srv)
              }, srv)
            if (!sp.isEmpty)
              sys.error("subqueries of groupBy cannot 'let' new temp tables: " + expr)
            Some(sq)
          }
        val joined: OrderedProcedure[DB, Record] = {
          (ord: List[(String, SortOrder)]) => (db: java.sql.Connection) =>
             val kord_ = ord.filter { p => knames.contains(p._1) }
             val kord = kord_ ++ (knames -- kord_.map(_._1)).map(n => (n, SortOrder.Asc))
             val v2ord = ord filterNot (kord_ contains)
             // this will actually run the outermost query, but this is prob
             // fine, since we are guarded by a function
             val rows: Procedure[scalaz.Id.Id, Record] = Mem.join { q(kord)(db).
               andThen(
                 Process.groupingBy((r: Record) => r.filterKeys(knames.contains).toMap)).
               map { case (key, recs) =>
                 val x = Literal(recs.head, recs.tail)
                 once match {
                   case Some(sq) =>
                     groupRows.set(x)
                     sq(v2ord)(db).map(_ ++ key)
                   case None =>
                     val subquery = Mem.instantiate(x, expr)
                     val MemPrg(sh, sp, sq, sr) = compileMem(subquery, smv, srv)
                     if (!sp.isEmpty)
                       sys.error("subqueries of groupBy cannot 'let' new temp tables: " + subquery)
                     else
                       sq(v2ord)(db).map(_ ++ key)
                 }
               }
             }
             rows andThen sorting(kord ++ v2ord, ord) andThen uniq(ord.map(_._1).toSet)
        }
        implicit val err: Typer.Errs[Option] = new Typer.Errs[Option] {
          def apply(s: String, msgs: String*): Option[Nothing] = None
        }
        val hdr = Typer.groupByType[Option](
          h, k.map(_.tuple).toMap,
          v => Typer.memTyper(Mem.instantiate(EmptyRel(v), expr).substPrg(srv andThen (_.q.h), smv andThen (_.h))).toOption).get
        MemPrg(hdr, p, joined, r.filterKeys(knames.contains))
      case ProcedureCall(args, h, proc, namespace)  => sys.error("TODO")
      case l@Literal(t,ts) =>
        MemPrg(l.header, List(),
          so => literalProcedure(l, so).point[DB],
          Reflexivity literalSeq (l.seq))
      case EmptyRel(h) => MemPrg(h, List(), _ => procedureFromSource(Machine.stopped).point[DB], KnownEmpty())
      case QuoteMem(n) => sys.error("Cannot scan quotes.")
      case ExceptM(m, cs) =>
        val MemPrg(h, p, q, rx) = compileMem(m, smv, srv)
        MemPrg(h -- cs, p, q andThen (_ andThen (_ map ((t: Record) => t -- cs))), rx)
      case ProjectM(m, cs) =>
        val MemPrg(h, p, q, rx) = compileMem(m, smv, srv)
        val renames = cs.filter( _._2.isInstanceOf[Op.ColumnValue]  )
        val renamesStr = renames map { case (a, o) => (a.name, o) }
        val rename = (s: String) => renamesStr.get(s).map( _.asInstanceOf[Op.ColumnValue].col ).getOrElse(s)
        val generalOps = cs -- renames.keys
        val generalOpsStr = generalOps map {case (a, o) => (a.name, o)}
        val mapRecord = (ops: Map[Attribute, Op]) => (proc:Procedure[scalaz.Id.Id, Record]) => proc.map(
          // Alexei: using RecordMap here for lesser memory footprint
          (t: Record) => RecordMap(ops.toSeq.map { case (attr, op) => attr.name -> op.eval(t) })
        )

        val needUniq = !preservesDistinctness(h, rx, cs)

        def nq(so: List[(String, SortOrder)]) = {
          val nonOpOrder = so.filter( s => renamesStr.contains(s._1) )
          val so2 = nonOpOrder.map( {case (s,o) => (rename(s), o)} )
          q(so2) map { case proc =>
            val proc2 = mapRecord(cs)(proc) andThen sorting(nonOpOrder, so)
            if (needUniq) proc2 andThen uniq(so.map(_._1).toSet) else proc2
          }
        }

        MemPrg(cs.map(_._1.tuple), p, nq, combineAll(rx, cs))
      case Pivot(under, pKey, pVals, outer, colMap) =>
        val MemPrg(h, p, q, rx) = compileMem(under, smv, srv)
        implicit val iderr: Typer.Errs[Id] = new Typer.Errs[Id] {
          def apply(x: String, xs: String*): Nothing = sys.error((x::xs.toList).mkString("\n"))
        }
        val nh = Typer.pivotType[Id](h, pKey, pVals, outer, colMap)
        val nq: OrderedProcedure[DB, Record] = (ord:List[(ColumnName,SortOrder)]) => {
          val idCols = h.keySet -- pKey -- pVals
          val myOrd = idCols.toList.map(c => (c, Asc))
          q(myOrd) map { p =>
            val pp = p.andThen(pivot(pKey,pVals,colMap,outer)).andThen(sorting(myOrd, ord))
            if(ord isEmpty) pp.andThen(uniq(idCols))
            else pp.andThen(uniq(ord.map(_._1).toSet))
          }
        }
        MemPrg(nh, p, nq, Reflexivity.zero)
      case AugmentSM(main, cur, hist) =>
        val MemPrg(h, p, q, rx) = compileMem(main, smv, srv)
        val (qq, hh, rxx) = sms.augment(h, rx, q, cur, hist)
        MemPrg(hh, p, qq, rxx)
      case x => sys.error("inconceivable! " + x)
  }

  /** The rows of a literal, sorted by `so`, as a procedure. */
  private[this] def literalProcedure(l: Literal, so: List[(String, SortOrder)]): Procedure[Id, Record] = {
    def src(rs: Stream[Record]): com.clarifi.machines.Source[Record] = rs match {
      case r #:: rs => Emit(r, () => src(rs))
      case _       => Stop
    }
    procedureFromSource(src(l.mapCollections( xs => sort(xs, so), xs => sort(xs, so)).toStream))
  }

  // `private[relational]` so `TestInMemoryScan` can drive the in-memory pivot.
  private[relational] def pivot(
    pKey: Set[ColumnName],
    pVals: Set[ColumnName],
    colMap: Map[ColumnName, (Record, Op, PrimExpr)],
    outer: Boolean
  ): Process[Record, Record] = {
    def collect(acc: Record, extra: Record): Process[Record, Record] =
      await[Record] flatMap { (r:Record) =>
        val nextra = r -- pKey -- pVals
        if (nextra == extra) { // we're on the same pivot row
          val kr = (r filterKeys pKey).toMap
          val vr = (r filterKeys pVals).toMap
          val newCols = colMap collect {
            case (c, (k,o,d)) if kr == k =>
              c -> o.eval(vr)
          }
          collect(acc ++ newCols, extra)
        } else {
          // TODO: check outer
          emit(extra ++ acc) flatMap { _ => prime(r) }
        }
      } orElse (emit(extra ++ acc) >> Stop)

    def prime(r: Record): Process[Record, Record] = {
      val extra = r -- pKey -- pVals
      // `.toMap`: since 2.13 `filterKeys` answers a lazy `MapView`, whose `equals`
      // is reference equality, so `kr == k` below was ALWAYS FALSE and the first
      // row of every group got each pivoted column's default (stage F3, ticket
      // A1b; `collect` above spells it correctly).
      val kr = (r filterKeys pKey).toMap
      val bootstrap : Record = colMap map {
        case (c, (k,o,d)) =>
          if (kr == k) c -> o.eval(r)
          else c -> d
      }

      collect(bootstrap, extra)
    }

    await[Record] flatMap prime
  }

  def memoProc[R,M](dbp: OrderedProcedure[DB, Record], m: MemoMem[R, M]): OrderedProcedure[DB, Record] = order => conn => {
    if (m.memo.isEmpty) {
      m.memo = dbp(order)(conn).foldLeftM(Vector[Record]())( (xs, x) => xs :+ x ).toList
      procedureFromSource( com.clarifi.machines.Source.source(m.memo))
    } else {
      procedureFromSource( com.clarifi.machines.Source.source( sort(m.memo, order)))
    }
  }

  def compileMerge[R,M](m1: Mem[R,M], m2: Mem[R,M],  smv: M => MemPrg, srv: R => SqlPrg, merge: Order[Record] => Tee[Record, Record, Record])(implicit sup: Supply, memoLookup: HashSet[TableName], scopeBuilder : List[() => String], letCache: LetCache) = {
        val r1 = compileMem(m1, smv, srv)
        val r2 = compileMem(m2, smv, srv)
        val MemPrg(h1, p1, q1, rx1) = r1
        val MemPrg(h2, p2, q2, rx2) = r2
        val totallyOrderedProcedure: OrderedProcedure[DB, Record] = order => {
          val cols = h1.keySet
          val unused = cols -- order.map(_._1)
          val totalOrder = order ++ unused.map( (_, Asc) )
          ^(q1(totalOrder), q2(totalOrder))(
            (q1p, q2p) => q1p.tee(q2p)( merge( recordOrd(totalOrder))))
          }
        MemPrg(h1, p1 ++ p2, totallyOrderedProcedure, rx1 || rx2)
   }

  private def readAll(h: Handle[T[Record, Record], Record] ): Tee[Record, Record, Record] = awaits(h).flatMap(emit).repeatedly

  private def mergeTee(ord: Order[Record]): Tee[Record, Record, Record] = {
    import Ordering._
    def loop(l:Record, r:Record): Tee[Record, Record, Record] =
      ord.order(l,r) match {
        case EQ => emit(l) >> mergeTee(ord)
        case LT => emit(l) >> awaits(left[Record]).flatMap( l2 => loop(l2, r) ).orElse(emit(r) >> readAll(right[Record]))
        case GT => emit(r) >> awaits(right[Record]).flatMap( r2 => loop(l, r2) ).orElse(emit(l) >> readAll(left[Record]))
      }

    awaits(left[Record]).flatMap( l => awaits(right[Record]).flatMap( r => loop(l,r)).orElse(emit(l) >> readAll(left[Record])))
      .orElse(readAll(right[Record]))
  }
  private def diffTee(ord: Order[Record]): Tee[Record, Record, Record] = {
    import Ordering._
    def loop(l:Record, r:Record): Tee[Record, Record, Record] =
      ord.order(l,r) match {
        case EQ => diffTee(ord)
        case LT => emit(l) >> awaits(left[Record]).flatMap( l2 => loop(l2, r) )
        case GT => awaits(right[Record]).flatMap( r2 => loop(l, r2) ).orElse(emit(l) >> readAll(left[Record]))
      }

    awaits(left[Record]).flatMap( l => awaits(right[Record]).flatMap( r => loop(l,r)).orElse(emit(l) >> readAll(left[Record])))
  }

  // `.toMap`: `Tee.hashJoin` HASHES the two key functions' answers and compares them.
  // Since 2.13 `filterKeys` answers a lazy `MapView`, which inherits `Object`'s
  // identity `hashCode`/`equals`, so no left key ever matched a right key and the
  // join emitted NOTHING (stage F3, ticket A1b; `mergeOuterJoin` at :421 and
  // `leftHashJoin` at :716 spell it correctly).  `private[relational]` so
  // `TestInMemoryScan` can drive it.
  /** A row whose join key holds a NULL: under SQL's `on (k = k)` it never
    * matches (decision D1), while in memory `NullExpr == NullExpr`, so the
    * hash joins matched NULL keys with NULL keys (prims' note on P2). */
  private[this] def nullKeyed(jk: Set[String])(r: Record): Boolean = jk.exists(c => r(c).isNull)

  private[relational] def hashJoin(q1: DB[Procedure[Id, Record]], q2: DB[Procedure[Id, Record]], jk: Set[String]) =
    ^(q1, q2)((q1, q2) => (q1 andThen Process.filtered((r: Record) => !nullKeyed(jk)(r)))
                            .tee(q2 andThen Process.filtered((r: Record) => !nullKeyed(jk)(r)))(
                              Tee.hashJoin((r: Record) => (r filterKeys jk).toMap,
                                           (r: Record) => (r filterKeys jk).toMap)).map(p => p._1 ++ p._2))

  private def leftHashJoin(dq1: DB[Procedure[Id, Record]],
                           dq2: DB[Procedure[Id, Record]],
                           jk: Set[String],
                           nulls: Record): DB[Procedure[Id, Record]] = {
    def build(m: Map[Record, Vector[Record]]): Plan[T[Record, Record], Nothing, Map[Record, Vector[Record]]] =
      awaits(right[Record]) flatMap { rr =>
        if (nullKeyed(jk)(rr)) build(m) else {
        val k = (rr filterKeys jk).toMap
        val v = m.getOrElse(k, Vector.empty)
        /* Alexei: short-circuit a degenerate case of adding the same record to the vector over and over again
                   otherwise memory use by issue browser tables explodes even in simple PA reports
        */
        val rr2 = if (v.isEmpty) Vector(rr)
        else {
          val last = v.last
          if (last == rr) v
          else v :+ rr
        }  
        
        val u = m.updated(k, rr2)

        build(u)
        }
      } orElse Return(m)
    def augments(m: Map[Record, Vector[Record]], r: Record): Vector[Record] =
      if (nullKeyed(jk)(r)) Vector(r ++ nulls)
      else m.lift((r filterKeys jk).toMap) match {
        case None => Vector(r ++ nulls)
        case Some(v) => v map (r ++ _)
      }
    def emits(v: Vector[Record]): Plan[T[Record, Record], Record, Unit] =
      v.foldr[Plan[T[Record, Record], Record, Unit]](Return(()))(e => k => Emit(e, () => k))
    ^(dq1, dq2)((q1, q2) =>
      q1.tee(q2)(build(Map()) flatMap { m =>
        awaits(left[Record]) flatMap { r =>
          emits(augments(m, r))
        } repeatedly
      }))
  }

  private def filterRx(rx: Reflexivity[ColumnName], p: Predicate) =
      rx && Predicates.constancies(p)

  // Uses Reflexivity to determine if a projection preserves distinctness
  private def preservesDistinctness(h: Header, rx: Reflexivity[ColumnName], cols: Map[Attribute, Op]): Boolean = {

    /** Only a bare column reference carries `col`'s distinctness through: any
      * other op over it (`coalesce`, `if`, `upper`, `abs`, `x * 0`, ...) can
      * send two values to one, and the old rule took every single-column op
      * as injective (oracle O-14, item C15). */
    def columnDistinctness(rx: Reflexivity[ColumnName], op: Op, col: ColumnName): Boolean = op match {
      case Op.ColumnValue(c, _) => c == col
      case _ => false
    }

    rx match {
      case KnownEmpty() => true
      case ForallTups(_, _) =>
        (h.keySet diff rx.consts.keySet) forall (c =>
            cols exists {
              case (_, op) => columnDistinctness(rx, op, c)
            })
    }
  }

  // Uses both reflexivity and fundeps to test if we think a projection preserves distinctness.
  // Only says 'yes' if both tests do so.
  private def megaDistinctness(h: Header, rx: Reflexivity[ColumnName], fds: Fundepped[ColumnName], cols: Map[Attribute, Op]) = {
    val rxPreserves = preservesDistinctness(h, rx, cols)
    val fdPreserves = Fundepped.preservesDistinctness(h, fds, cols)
    if (rxPreserves != fdPreserves)
      logger.debug {
        "reflexivity and fundeps gave different distinctness answers:\n" +
        "  reflexivity: " + rxPreserves.toString + "\n" +
        "      fundeps: " + fdPreserves.toString + "\n"
      }

    rxPreserves && fdPreserves
  }

  private def combineAll(rx: Reflexivity[ColumnName],
                         comb: Map[Attribute, Op],
                         keepOld: Boolean = false) =
    rx combineAll (mapKeys(comb)(_.name), {case x => x}, identity, keepOld)

  private def joinReflexivity(rxl: Reflexivity[ColumnName],
                              rxr: Reflexivity[ColumnName],
                              mode: JoinMode): Reflexivity[ColumnName] = mode match {
    case JoinMode.Inner => rxl && rxr
    case JoinMode.Left => rxl
    case JoinMode.Right => rxr
    case JoinMode.Full => Reflexivity.zero
  }

  private def joinAttrs(lattrs: Map[SqlColumn, SqlExpr],
                        rattrs: Map[SqlColumn, SqlExpr],
                        mode: JoinMode): Map[SqlColumn, SqlExpr] = mode match {
    case JoinMode.Inner | JoinMode.Left => rattrs ++ lattrs
    case JoinMode.Right => lattrs ++ rattrs
    case JoinMode.Full =>
      val inter = lattrs collect {
            case (col, lexp) if rattrs.isDefinedAt(col) =>
              col -> FunSqlExpr("coalesce", List(lexp, rattrs(col)))
          }
      lattrs ++ rattrs ++ inter
  }

  def compileRel[M,R](m: Relation[M, R], smv: M => MemPrg,
                      srv: R => SqlPrg)(implicit sup: Supply, memoLookup: HashSet[TableName]
                      , scopeBuilder: List[() => String], letCache: LetCache
                      ): SqlPrg = {

    def combineBinary(
      l: Relation[M, R],
      r: Relation[M,R],
      f: (DistinctiveQuery, DistinctiveQuery) => DistinctiveQuery,
      g: (Reflexivity[ColumnName], Reflexivity[ColumnName]) => Reflexivity[ColumnName]) = {
      val SqlPrg(p1, ns1, q1, refl1) = compileRel(l, smv, srv)
      val SqlPrg(p2, ns2, q2, refl2) = compileRel(r, smv, srv)
      SqlPrg(p1 ++ p2, ns1 ++ ns2, f(q1, q2), g(refl1, refl2))
    }

    m match {
      case VarR(v) => srv(v)
      case JoinOn(l, r, on, mode) =>
        combineBinary(l, r, _ joinOn (on, _, mode), joinReflexivity(_, _, mode)) // TODO: verify
      case Union(l, r) =>
         // TODO: be smarter about fundeps if possible
        combineBinary(l, r, _ union _, _ || _)
      case Minus(l, r) =>
        combineBinary(l, r, _ minus _, _ || _)
      case Filter(r, pred) =>
        val SqlPrg(p, ns, q, rx) = compileRel(r, smv, srv)
        val pred1 = simplifyPredicate(pred, rx)
        SqlPrg(p, ns, q.filter(pred1), filterRx(rx, pred))
      case Project(r, cols) =>
        val SqlPrg(p, ns, q, rx) = compileRel(r, smv, srv)
        SqlPrg(p,
               ns,
               q project (cols,rx),
               combineAll(rx, cols))
      case AggregateByGroup(r,cs,aggs,group) =>
        val SqlPrg(p, ns, q, _) = compileRel(r, smv, srv)
        SqlPrg(p, ns, q.aggregateByGroup(cs,aggs,group),
          Reflexivity.zero)
      case Aggregate(r, attr, f) =>
        val SqlPrg(p, ns, q, _) = compileRel(r, smv, srv)
        SqlPrg(p, ns, q.aggregate(attr, f),
          ForallTups(Map(attr.name -> None), PartitionedSet.zero))
      case Except(r, cs) =>
        val SqlPrg(p, ns, q, rx) = compileRel(r, smv, srv)
        SqlPrg(p, ns, q except (cs, rx), rx filterKeys (!cs.contains(_)))
      case Combine(r, attr, op) =>
        val SqlPrg(p, ns, q, rx) = compileRel(r, smv, srv)
        SqlPrg(p, ns, q combine (attr, op, rx),
          combineAll(rx, Map(attr -> op), true))
      case Limit(r, from, to, order) =>
        val SqlPrg(p, ns, q, rx) = compileRel(r, smv, srv)

        // Limiting to one row or less necessarily makes all things constant.
        // `from`/`to` are 1-based and INCLUSIVE (Sort.e, `emitLimit`), so
        // (f, t) is one row iff t == f; `t - f < 2` counted a two-row range as
        // one and the projection above it skipped its DISTINCT (audit L-4).
        val nrx = (from, to) match {
          case (Some(f), Some(t)) if t-f < 1 =>
            ForallTups(q.h.map{ case (k, _) => k -> None}, PartitionedSet.zero)
          case _ => rx
        }

        SqlPrg(p, ns, q limit (from, to, order), nrx)

      case Table(h, n) => SqlPrg(List(), List(), DistinctiveQuery.table(h, n), Reflexivity.zero)
      case TableProc(args, oh, src, namespace) =>
        val h = oh.toMap
        val argable = TableProc.argFunctor.map(args){case (typeName, r) =>
          (TableName(guidName, List(), TableName.Variable(typeName)),
           compileRel(r, smv, srv))}
        val un = guidName
        val sink = TableName(un, List(), TableName.Temporary)
        SqlPrg(TableProc.argFoldable.foldMap(argable)(_._2.prg.toIndexedSeq)
                  :+ SqlCreate(table = sink, header = h)
                  :+ SqlExec(sink, src, namespace,
                             TableProc.argFoldable.foldMap(argable){
                               case (unt, SqlPrg(_, _, iq, _)) => // TODO: notes?
                                 fillTable(unt, iq.h, iq.distinctQuery)
                             }, oh map (_._1),
                             argable map (_ bimap (_._1,
                                                   SqlExpr.compileLiteral)))
                 toList,
               List(),
               DistinctiveQuery.table(h, sink),
               Reflexivity.zero)
      case RelEmpty(h) =>
        SqlPrg(List(), List(), DistinctiveQuery.empty(h), KnownEmpty())
      case PivotR(under, pKey, pVals, outer, colMap) =>
        val SqlPrg(p, ns, q, rx) = compileRel(under, smv, srv)
        val preCols = q.h.keySet -- pKey -- pVals
        SqlPrg(p, ns, q pivot (pKey, pVals, outer, colMap), Reflexivity.zero)
      case QuoteR(_) => sys.error("Cannot scan quotes")
      case l@SmallLit(ts) =>
        if (ts.size <= 100) {
            SqlPrg(List(), List(), DistinctiveQuery.literal(l), Reflexivity literal ts)
        } else {
            val h = l.header
            val un = guidName
            val n = TableName(un, List(), TableName.Temporary)
            SqlPrg(List(SqlCreate(table = TableName(un, List(), TableName.Temporary),
                                  header = h),
                        SqlLoad(TableName(un, List(), TableName.Temporary), h, procedureFromSource(com.clarifi.machines.Source.source(ts.toList)).point[DB])),
               List[String](),
                   DistinctiveQuery.table(h, n),
                   Reflexivity literal ts)
        }
      case MemoR(r,pk) => {
        val rc = compileRel(r,smv,srv)
        // val relHash = "MemoHash_" + (r, scopeBuilder).##.toString
        val scopeStr : List[String] = scopeBuilder.map(mkstr => mkstr())
        val relHash = "MemoHash_" + java.security.MessageDigest.getInstance("SHA").digest(s"$r\n$scopeStr".getBytes("UTF-8")).map("%02x" format _).mkString
        val myTN = TableName(relHash, List(), TableName.Persistent)
        val myHints = if (pk.isEmpty) { TableHints.empty } else { TableHints.empty.reorder(pk).withPK(SortedSet(pk: _*)) }
        val createWithKey :: fillStat = fillTable(myTN, rc.q.h, rc.q.distinctQuery, myHints)
        val myPrg = List(SqlCreateIfNotExists(myTN, rc.prg, createWithKey, fillStat))
        SqlPrg(myPrg, List(), DistinctiveQuery.table(rc.q.h, myTN), rc.refl)
      }
      case LetR(ext, pk, exp)
          if exp.bifoldMap((_: M) => 0, (v: RLevel[M, R]) => v match { case RTop => 1; case RPop(_) => 0 }) == 0 =>
        // The body never uses the binding: no temp table is made or filled
        // (oracle O-19, item C20).
        compileRel(exp, smv, (v: RLevel[M, R]) => v match {
          case RTop => sys.error("Panic: an unused let binding was referenced")
          case RPop(e) => compileRel(e, smv, srv)
        })
      case LetR(ext, pk, exp) =>
        def materialise: (Header, Reflexivity[ColumnName], List[SqlStatement], TableName) = {
          val un = guidName
          val tn = TableName(un, List(), TableName.Temporary)
          val hnt = if (pk.isEmpty) { TableHints.empty } else { TableHints.empty.reorder(pk).withPK(SortedSet(pk: _*)) }
          ext match {
            case ExtRel(rel, _) => // TODO: Handle namespace
              val SqlPrg(ip, _, iq, rx) = compileRel(rel, smv, srv) // TODO: do something with notes
              (iq.h, rx, ip ++ fillTable(tn, iq.h, iq.distinctQuery, hnt), tn)
            case ExtSM(sm) =>
              val (pop, h, rx) = sms(sm)
              (h, rx,
                List(SqlCreate(
                       table = tn, header = h, hints = hnt),
                     SqlLoad(tn, h, pop(List()))), tn)
            case ExtMem(mem) =>
              val m = compileMem(mem, smv, srv)
              val MemPrg(h, p, pop, rx) = m
              (h, rx,
                p ++ List(SqlCreate(table = tn, header = h, hints = hnt),
                          SqlLoad(tn, h, pop(List()))), tn)
          }
        }
        // See `LetCache`: a closed `ext` is materialised once per scan.
        val closed = ext.bifoldMap((_: M) => 1, (_: R) => 1) == 0
        val (ih, rx1, ps, tn) =
          if (closed) letCache.getOrElseUpdate(ext, pk, materialise)
          else materialise
        val SqlPrg(p, ns, q, rx2) = compileRel(exp, smv, (v: RLevel[M,R]) => v match {
          case RTop => SqlPrg(List(), List(), DistinctiveQuery.table(ih, tn), rx1)
          case RPop(e) => compileRel(e, smv, srv)
        })(sup, memoLookup, (() => ext.toString) :: scopeBuilder, letCache)
        SqlPrg(ps ++ p, ns, q, rx2)
      case Note(ns, under) =>
        val SqlPrg(stmts, notes, q, rx) = compileRel(under, smv, srv)
        SqlPrg(stmts, ns ++ notes, q, rx)
      case RenameR(r, attr@Attribute(from, ty), to) =>
        val SqlPrg(p, ns, q, rx) = compileRel(r, smv, srv)
        SqlPrg(p,
               ns,
               q rename (attr, to),
               combineAll(rx, Map(Attribute(to, ty) -> Op.ColumnValue(from, ty)), true) filterKeys (from != _))
    }
  }

  private object DistinctiveQuery {

    import emitter.distinctEagerly

    def columns(h: Header, rv: TableName) = h.transform((k,v) => ColumnSqlExpr(rv, k))

    private[DistinctiveQuery]
    def selectOps(sel: Map[Attribute,Op], col: String => SqlExpr): Map[ColumnName, SqlExpr] =
      sel map { case (attr, op) =>
        attr.name -> compileOp(op, col)
      }

    private[DistinctiveQuery]
    def selectWindows(sel: Map[Attribute,Op], subWindows: Set[SqlColumn]): Set[SqlColumn] = {
      sel.toList.flatMap {
        case (attr,op) =>
          if (op.isWindowed || (op.columnReferences intersect subWindows).nonEmpty)
            List(attr.name)
          else List()
      } toSet
    }

    private[DistinctiveQuery]
    def selectWrap(h: Header, q: SqlQuery.Nestable)(implicit sup: Supply): SqlSelect = {
      val un = TableName(freshName)
      val src = emitter.implementSubquery(q, h, un)
      SqlSelect(attrs = columns(h, un), sources = SourceList(src))
    }

    private[DistinctiveQuery]
    def asSelect(h: Header, q: SqlQuery.Nestable, cond: SqlSelect => Boolean = (_ => true))(implicit sup: Supply): SqlSelect =
      q match {
        case v: SqlSelect if cond(v) => v
        case _ => selectWrap(h,q)
      }

    // not private since it's called from outside
    def asOrderable(h: Header, q: SqlQuery.Nestable, cond: SqlQuery.Orderable => Boolean = (_ => true))(implicit sup: Supply): SqlQuery.Orderable =
      q match {
        case v: SqlQuery.Orderable if cond(v) => v
        case _ => selectWrap(h,q)
      }

    private[DistinctiveQuery]
    def satisfyDistinct(hasDistinct: Boolean, needDistinct: Boolean, h: Header, q: SqlQuery.Scannable with SqlQuery.Nestable)(implicit sup: Supply): (Boolean, SqlQuery.Scannable with SqlQuery.Nestable) =
      if(hasDistinct || !needDistinct) (hasDistinct, q)
      else (true, asSelect(h,q) match {
        case sel => sel copy (options = sel.options + "distinct")
      })

    def table(h: Header, n: TableName)(implicit sup: Supply): DistinctiveQuery = {
      val un = TableName(freshName)
      val src = FromTable(n, h.keys.toList, Some(un))
      val result = (true, SqlSelect(attrs = columns(h, un), sources = SourceList(src)))
      DistinctiveQuery(h, _ => result)
    }

    /** A literal is distinct only when its rows are: a table-value constructor
      * keeps duplicate rows (SQL Server), the union-of-selects form drops them
      * by accident (SQLite), and the consumer trusted `true` (oracle O-2). */
    def literal(l: SmallLit)(implicit sup: Supply): DistinctiveQuery = {
      val rows = l.tups.list.toList
      val distinct = rows.distinct.size == rows.size
      DistinctiveQuery(l.header, _ => (distinct, LiteralSqlTable(l.tups.map(r => r.mapValues(x => SqlExpr.compileLiteral(x)).toMap))))
    }

    def empty(h: Header)(implicit sup: Supply): DistinctiveQuery = {
      DistinctiveQuery(h, _ => (true, SqlEmpty(h)))
    }
  }

  private[SqlScanner]
  case class DistinctiveQuery(val h: Header, val q: Boolean => (Boolean, SqlQuery.Scannable with SqlQuery.Nestable)) {
    import DistinctiveQuery.{ selectOps, selectWindows }

    private[this] def guidName = "t" + sguid
    private[this] def freshName(implicit sup: Supply) = "t" + sup.fresh

    import DistinctiveQuery.{satisfyDistinct, columns, asSelect, asOrderable, selectWrap}
    import emitter.distinctEagerly

    /** The query with distinct rows, made so here when the inner query could
      * not (a literal with duplicate rows): what fills a temp, memo or
      * procedure-argument table, which `table` then rightly claims distinct
      * (oracle O-2 through `LetR`). */
    def distinctQuery(implicit sup: Supply): SqlQuery.Scannable with SqlQuery.Nestable =
      q(true) match { case (d, q0) => satisfyDistinct(d, true, h, q0)._2 }

    /** The operand of a set operation, grouped explicitly (wrapped in a select)
      * when it is itself a set operation of ANOTHER kind, or the right operand
      * of EXCEPT: `A UNION B EXCEPT C` is `(A UNION B) EXCEPT C` on SQL Server
      * and Postgres (UNION and EXCEPT bind alike, left-associatively), so a
      * nested tree emitted flat meant something else (audit L-2, decision D5:
      * in the scanner, for every dialect; SQLite's emitter wraps every operand
      * anyway).  One level of the emitted text then holds one operator, and
      * how a dialect associates it no longer matters. */
    private[this] def grouped(q: SqlQuery.Scannable with SqlQuery.Nestable, under: SqlBinOp, rightOfExcept: Boolean)
                             (implicit sup: Supply): SqlQuery.Orderable = q match {
      case SqlNaryOp(op, _) if rightOfExcept || (op.getClass != under.getClass) => selectWrap(h, q)
      case _ => asOrderable(h, q)
    }

    def union(other: DistinctiveQuery)(implicit sup: Supply): DistinctiveQuery =
      DistinctiveQuery(h, needDistinct =>
        (q(false), other.q(false)) match {
          case ((d1, q1), (d2, q2)) =>
            (true, SqlUnion(grouped(q1, SqlUnion, false), grouped(q2, SqlUnion, false)))
        })

    /** EXCEPT answers a set on every dialect that has it (SQL Server, SQLite,
      * Postgres, Vertica), so the left arm need not be made distinct and the
      * result IS distinct; only the MySQL emulation as a LEFT JOIN keeps the
      * left arm's multiplicity, and there the old shape stays (audit L-19 b,
      * O-26). */
    def minus(other: DistinctiveQuery)(implicit sup: Supply): DistinctiveQuery = {
      val ur = freshName
      val exceptIsSet = emitter match {
        case _: EmitNary_ExceptAsJoin => false
        case _ => true
      }
      DistinctiveQuery(h, needDistinct =>
        (q(needDistinct && !exceptIsSet), other.q(false)) match {
          case ((d, q1), (_, q2)) =>
            // No need for the thing we're subtracting to be distinct
            val ex = SqlExcept(TableName(ur), h)
            val diff = SqlDifference(TableName(ur), h, grouped(q1, ex, false), grouped(q2, ex, true))
            if (exceptIsSet) (true, diff)
            else satisfyDistinct(d, needDistinct, h, diff)
        })
    }

    /** A one-row literal joined to `q` becomes an equality predicate on `q`'s
      * select and the literal's constants in its select list.  The select is
      * wrapped first when it is WINDOWED (the predicate would otherwise filter
      * the rows BEFORE the window function ranks them, and a predicate on the
      * window column itself is rejected by T-SQL: audit L-3, O-3) or AGGREGATED
      * (the predicate would become a HAVING and the literal's constant would
      * replace the GROUP BY column with a constant, which `SqlSelect.emitSql`
      * drops from the GROUP BY, so an empty input answered one row: oracle
      * O-15).  Wrapped, the predicate is a plain WHERE on the outer select. */
    def squashLiteral(attrs: Map[SqlColumn, SqlExpr], h: Header, q: SqlQuery.Scannable with SqlQuery.Nestable, on: Set[(String,String)], mode: JoinMode)
                     (implicit sup: Supply): SqlSelect = {
      val v = asSelect(h, q, v => !v.isWindowed && !v.isAggregated)
      val preds = on.toList.map {
        case (l,r) => SqlEq(v.attrs(r),attrs(l))
      }
      v.copy(attrs = v.attrs ++ attrs,
             where = v.where ++ preds)
    }

    def joinOn(on: Set[(String, String)], other: DistinctiveQuery, mode: JoinMode)(implicit sup: Supply): DistinctiveQuery = {
      (q(distinctEagerly), other.q(distinctEagerly)) match {
        case ((d1, q1), (d2, q2)) =>
          // include duplicately-named columns from the header to match the way Ermine types this
          //  -- it also matches our smart Join constructor which doesn't have the information
          //  available to add them.
          val allOn = on ++ (h.keySet intersect other.h.keySet map {x => (x,x)})
          val q3 = q1 match {
            case (SqlSingle(row)) if mode == JoinMode.Inner =>
              squashLiteral(row,other.h,q2,allOn,mode)
            case _ =>
              q2 match {
                case (SqlSingle(row)) if mode == JoinMode.Inner =>
                  squashLiteral(row,h,q1,allOn map {_.swap},mode.reverse)
                case _ =>
                  // The side an outer join pads with NULLs is merged into the
                  // join's select only when its select list is plain column
                  // references: a constant or `coalesce` in it would be
                  // computed on the padded rows too, where the answer must be
                  // NULL (audit O-4); its WHERE would filter the join instead
                  // of the side.
                  def plainColumns(v: SqlSelect) = v.attrs.values.forall {
                    case _: ColumnSqlExpr => true
                    case _ => false
                  }
                  val v1 = asSelect(h,q1, v => !v.isAggregated
                                            && !v.sources.sources.isEmpty
                                            && !v.isWindowed
                                            && (mode match {
                                                 case JoinMode.Right | JoinMode.Full => v.where.isEmpty && plainColumns(v)
                                                 case _ => true
                                               }))
                  val v2 = asSelect(other.h,q2, v => !v.isAggregated
                                                  && !v.sources.sources.isEmpty
                                                  && !v.isWindowed
                                                  && (mode match {
                                                       case JoinMode.Left | JoinMode.Full => v.where.isEmpty && plainColumns(v)
                                                       case _ => true
                                                     }))
                  v1.copy(sources = SourceList(
                                      SqlJoinOn(
                                        v1.sources.asSource.get,
                                        v2.sources.asSource.get,
                                        allOn map {case (c1,c2) => (v1.attrs(c1),
                                                                    v2.attrs(c2))},
                                        compileJoinMode(mode)
                                      )
                                    ),
                          attrs = joinAttrs(v1.attrs, v2.attrs, mode),
                          options = v2.options ++ v1.options, // XXX assumes distinct is the
                                                              // only option!
                          where = v1.where ++ v2.where
                         )
              }
          }
          // The side an outer join pads is typed NULLABLE in the header the
          // rows are decoded with, else an unmatched row's NULL is refused at
          // decode time (decision D4; `Typer.joinHeader` says the same for the
          // document's types).  A join column keeps the type of the side whose
          // value the select list takes (`joinAttrs`); on a FULL join it is
          // coalesced, so it stays as the left side has it.
          def padded(side: Header, other: Header): Header =
            (side -- other.keySet).map { case (c, t) => (c, t.withNull) }
          val jh: Header = mode match {
            case JoinMode.Inner => other.h ++ h
            case JoinMode.Left  => padded(other.h, h) ++ h
            case JoinMode.Right => padded(h, other.h) ++ other.h
            case JoinMode.Full  =>
              // a shared column is `coalesce(l, r)`: NULL when the one side
              // present has a NULL there, so nullable iff EITHER side's is
              // (`Typer.joinHeader`'s rule; review-scanner's must-fix)
              padded(other.h, h) ++ padded(h, other.h) ++ (h filterKeys other.h.keySet).toMap.map {
                case (c, t) => (c, if (t.nullable || other.h(c).nullable) t.withNull else t)
              }
          }
          // An outer join over a NULLABLE join column cannot claim distinct
          // output: a left-only and a right-only row whose keys are NULL
          // coalesce to equal rows (oracle O-28, item C16).
          val nullableKey = mode != JoinMode.Inner && allOn.exists {
            case (c1, c2) => h.get(c1).exists(_.nullable) || other.h.get(c2).exists(_.nullable)
          }
          DistinctiveQuery(jh, nd => satisfyDistinct(d1 && d2 && !nullableKey, nd, jh, q3))
        }
    }

    /** A filter over a UNION is pushed into every arm (σ(A ∪ B) = σ(A) ∪ σ(B),
      * under three-valued logic too), so each arm is filtered before the union
      * dedupes it instead of after (audit O-15).  Everything else takes the
      * predicate in its WHERE, or its HAVING when aggregated. */
    def filter(pred: Predicate)(implicit sup: Supply): DistinctiveQuery = {
      def filtered(q: SqlQuery.Nestable): SqlSelect =
        asSelect(h, q, v => !v.isWindowed) match {
          case v =>
            if (v.isAggregated)
              v.copy(having = compilePredicate(pred, v.attrs) :: v.having)
            else
              v.copy(where  = compilePredicate(pred, v.attrs) :: v.where )
        }
      DistinctiveQuery(h, needDistinct => q(distinctEagerly) match {
        case (d, SqlNaryOp(SqlUnion, arms)) =>
          // every `Orderable` the scanner builds is `Nestable` too
          satisfyDistinct(d, needDistinct, h, SqlNaryOp(SqlUnion, arms.map { case a: SqlQuery.Nestable => filtered(a): SqlQuery.Orderable }))
        case (d, q) => satisfyDistinct(d, needDistinct, h, filtered(q))
      })
    }

    /** An ungrouped aggregate over NO rows (decision D2, audit L-6, S-09,
      * E-13): SUM answers 0 (`coalesce(SUM(x), 0)`, the typed zero of the
      * result column) and COUNT 0 as SQL does already; MIN, MAX, AVG, STDDEV,
      * VARIANCE and the weighted means answer NO ROW (`having count(*) > 0`)
      * instead of one NULL row into a column typed non-nullable, which the
      * decoder refused.  Grouped aggregates are unchanged: an absent group is
      * absent.  The in-memory `AggregateM` follows the same rule (prims P4). */
    def aggregate(attr: Attribute, f: AggFunc)(implicit sup: Supply): DistinctiveQuery = {
      DistinctiveQuery(Map(attr.name -> attr.t), _ => q(true) match {
        case (d0, q0) => (true, {
          // An aggregate is over a SET: an input that could not make itself
          // distinct (a literal with duplicate rows) is made so here; the
          // inner answer used to be ignored (oracle O-2 through this path).
          val (_, q) = satisfyDistinct(d0, true, h, q0)
          val v = asSelect(h, q, x => !x.isAggregated && !x.options("distinct") && !x.isWindowed)
          val agg = compileAggFunc(f, v.attrs)
          f match {
            case Count =>
              v.copy(attrs = Map(attr.name -> agg), isAggregated = true)
            case Sum(_) =>
              v.copy(attrs = Map(attr.name -> FunSqlExpr("coalesce", List(agg, compileLiteral(PrimExpr.sumMonoid(attr.t).zero)))),
                     isAggregated = true)
            case _ =>
              v.copy(attrs = Map(attr.name -> agg),
                     having = v.having :+ SqlGt(FunSqlExpr("COUNT", List(Verbatim("*"))), LitSqlExpr(SqlInt(0))),
                     isAggregated = true)
          }
        })
      })
    }

    def aggregateByGroup(cs: Map[Attribute,Op],
                         aggs: List[(Attribute,AggFunc)],
                         group: List[Op.ColumnValue]
                        )(implicit sup: Supply): DistinctiveQuery = {
      val (d0, sq0) = q(true) // to aggregate, we need distinctness
      val (_, sq) = satisfyDistinct(d0, true, h, sq0) // and make it so when the input could not (oracle O-2)
      val v = asSelect(h, sq, x => !x.isAggregated && !x.options("distinct") && !x.isWindowed)
      val q2 = v.copy(attrs = cs.map { case (attr, op) =>
                                attr.name -> compileOp(op, v.attrs)
                              } ++
                              aggs.map {
                                case (attr, f) =>
                                  attr.name -> compileAggFunc(f, v.attrs)
                              }.toMap,
                      groupBy = group map (compileOp(_, v.attrs)),
                      isAggregated = true )
      DistinctiveQuery(cs.map(_._1.tuple) ++ aggs.map(_._1.tuple), _ => (true, q2))
    }

    /** A projection of a grouped aggregate that keeps every GROUP BY column as
      * a plain column reference keeps the rows distinct: the group columns are
      * a key of the aggregate's output, which `Reflexivity` cannot say (audit
      * L-19 a). */
    private[this] def keepsGroupKey(v: SqlSelect, attrs: Map[SqlColumn, SqlExpr]): Boolean =
      v.isAggregated && v.groupBy.nonEmpty && v.groupBy.forall(g => attrs.values.exists(_ == g))

    /** An UNGROUPED aggregate select whose output the projection does not
      * reference (`project {p = 3} (sumBy x r)`) can not be projected in
      * place: without an aggregate function in its select list it is no longer
      * an aggregate query and answers one row PER INPUT ROW (oracle O-9).  Such
      * a select is wrapped. */
    private[this] def dropsUngroupedAggregate(v: SqlSelect, cols: Map[Attribute, Op]): Boolean =
      v.isAggregated && v.groupBy.isEmpty && cols.values.forall(_.columnReferences.isEmpty)

    /** Distinctness is asked of the inner query only when the CONSUMER needs it
      * and this projection can pass it on (`needDistinct && preservesDistinct`),
      * not eagerly: an eager `select distinct` under a UNION arm, an EXCEPT arm
      * or a join was a sort the consumer repeated (audit O-12, O-26).  The
      * top-level scan still asks for distinctness, so results are unchanged. */
    def project(cols: Map[Attribute,Op], rx: Reflexivity[ColumnName])(implicit sup: Supply): DistinctiveQuery = {
      val resultHeader = cols.map(_._1.tuple)
      val preservesDistinct = preservesDistinctness(h, rx, cols)
      DistinctiveQuery(resultHeader, needDistinct => q(needDistinct && preservesDistinct) match {
        case (d, q) =>
          val v = asSelect(h, q, s => !dropsUngroupedAggregate(s, cols))
          val q2 = v.copy(attrs = selectOps(cols, v.attrs),
                          windowColumns = selectWindows(cols, v.windowColumns))
          satisfyDistinct(d && (preservesDistinct || keepsGroupKey(v, q2.attrs)), needDistinct, resultHeader, q2)
      })
    }

    def rename(attr: Attribute, to: ColumnName)(implicit sup: Supply): DistinctiveQuery = {
      val resultHeader = h - attr.name + (to -> attr.t)
      DistinctiveQuery(resultHeader, distinct => q(distinct) match {
        case (d, q) =>
          val q2 = asSelect(h,q)
          val nattrs = q2.attrs - attr.name + (to -> q2.attrs(attr.name))
          val nwinCs =
            if (q2.windowColumns.contains(attr.name)) q2.windowColumns - attr.name + to
            else q2.windowColumns
          (d, q2.copy(attrs = nattrs, windowColumns = nwinCs))
      })
    }

    def except(cols: Set[ColumnName], rx: Reflexivity[ColumnName])(implicit sup: Supply): DistinctiveQuery = {
      val resultHeader = h -- cols
      val colOps = resultHeader map { case (c,t) => Attribute(c,t) -> Op.ColumnValue(c,t) }
      val preservesDistinct = preservesDistinctness(h, rx, colOps)
      DistinctiveQuery(resultHeader, needDistinct => q(needDistinct && preservesDistinct) match {
        case (d, q) =>
          val v = asSelect(h, q, s => !dropsUngroupedAggregate(s, colOps))
          val q2 = v.copy(attrs = v.attrs -- cols, windowColumns = v.windowColumns -- cols)
          satisfyDistinct(d && (preservesDistinct || keepsGroupKey(v, q2.attrs)), needDistinct, resultHeader, q2)
      })
    }

    def combine(attr: Attribute, op: Op, rx: Reflexivity[ColumnName])(implicit sup: Supply): DistinctiveQuery =
      project(Header.proj(h) + (attr -> op), rx)

    def limit(from: Option[Int], to: Option[Int], order: List[(String,SortOrder)])(implicit sup: Supply): DistinctiveQuery = {
      val fromn = from.getOrElse(1)
      // limit may return 1 or 0 rows.  1 row obviates distinct in the inner query, 0 obviates
      // the whole query.  if it may return more than 1 row, distinctness is needed on the
      // inner query to get semantically correct results.
      (fromn, to) match {
        case (1, None) => this
        case (_, Some(j)) if j < fromn => DistinctiveQuery.empty(h)
        case _ =>
          val isOneRow = Some(fromn) == to
          // Only the FIRST row of a bag is the first row of its set under the
          // same order; at any later position a duplicate shifts which row is
          // the n-th, so every other range needs a distinct input, made so
          // here when the inner query could not (oracle O-26, item C17).
          val needInner = !(isOneRow && fromn == 1)
          val u1 = TableName(freshName)
          val u2 = TableName(freshName)
          DistinctiveQuery(h, needDistinct => q(needInner) match {
            case (d0, q0) =>
              val (d, q) = if (needInner) satisfyDistinct(d0, true, h, q0) else (d0, q0)
              val actualOrder = if (!order.isEmpty) order
                                else h.map { case (k,t) => (k, SortOrder.Asc) }.toList
              satisfyDistinct(d || isOneRow, needDistinct, h, emitter.implementLimit(asOrderable(h,q), h, u1, from, to, actualOrder.map {
                case (k, v) => (k, v(asc = SqlAsc, desc = SqlDesc))
              }, u2))
        })
      }
    }

    def pivot(key: Set[ColumnName], vals: Set[ColumnName], outer: Boolean, colMap: Map[ColumnName, (Record, Op, PrimExpr)])(implicit sup: Supply): DistinctiveQuery = {
      implicit val iderr: Typer.Errs[Id] = new Typer.Errs[Id] {
          def apply(x: String, xs: String*): Nothing = sys.error((x::xs.toList).mkString("\n"))
        }
      val nh = Typer.pivotType[Id](h, key, vals, outer, colMap)
      val sel = asSelect(h, q(false)._2, v => !v.isAggregated && !v.isWindowed)
      val extra = h -- key -- vals
      val allKeys = colMap.values.map(_._1).toSet
      val q2 = sel.copy(isAggregated = true,
                        groupBy = extra.toList map (x => sel.attrs(x._1)),
                        options = sel.options - "distinct",
                        attrs = sel.attrs -- key -- vals ++ colMap.mapValues {
                          case (r, op, defval) =>
                            FunSqlExpr("coalesce", List(
                              compileAggFunc(Max(Op.If(Predicate.fromRecord(r),
                                                       op,
                                                       Op.OpLiteral(NullExpr(defval.typ)))),
                                             sel.attrs
                                            ),
                              compileLiteral(defval)
                            ))
                        },
                        where = SqlPredicate.fromLiteral(sel.attrs, allKeys.toList) ++ sel.where)
      DistinctiveQuery(nh, _ => (true, q2))
    }
  }
}
