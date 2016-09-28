package com.clarifi.reporting
package relational

import java.sql.SQLException

import com.clarifi.reporting._
import com.clarifi.reporting.sql._
import com.clarifi.reporting.backends._
import com.clarifi.reporting.util.PartitionedSet
import DB._
import ReportingUtils.simplifyPredicate
import SqlExpr._

import scalaz._
import scalaz.Coproduct._
import scalaz.IterV._
import scalaz.Id._
//import Scalaz.{^ => _, _}
import scalaz.std.indexedSeq.{toNel => _, _}
import scalaz.std.vector.{toNel => _, _}
import scalaz.std.map._
import scalaz.std.function._
import scalaz.std.option._
import scalaz.std.list._
import scalaz.std.string._
import scalaz.std.anyVal._

import scalaz.syntax.monad._
import scalaz.syntax.traverse.{ToFunctorOps => _, _}
// important for instance resolution.
import scala.collection.immutable.IndexedSeq
import scala.collection.immutable.SortedSet

import com.clarifi.machines._
import Plan.{ await, awaits, emit }
import Tee.{ right, left }

import scalaparsers.Supply
import org.apache.log4j.Logger
import com.clarifi.reporting.util.PimpedLogger._
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

  private[this] def logger = Logger getLogger this.getClass

  import AggFunc._

  private[this] def fillTable(table: TableName, header: Header, from: SqlQuery
                             ): List[SqlStatement] = {
    val c = SqlCreate(table = table, header = header)
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
      case If(test, conseq, altern) => (rec(conseq), rec(altern)) match {
        case (cConseq, CaseSqlExpr(clauses, oth)) =>
          CaseSqlExpr((compilePredicate(test, lookupColumn),
                       cConseq) <:: clauses, oth)
        case (CaseSqlExpr(clauses, oth), cAltern) =>
          CaseSqlExpr((compilePredicate(Predicate.Not(test), lookupColumn),
                       cAltern) <:: clauses, oth)
        case (cConseq, cAltern) =>
          CaseSqlExpr(NonEmptyList((compilePredicate(test, lookupColumn),
                                    cConseq)),
                      ParensSqlExpr(cAltern))
      }
      case Coalesce(l, r) =>
        FunSqlExpr("coalesce", List(rec(l),rec(r)))
      case DateAdd(d, n, u) =>
        FunSqlExpr(emitter.emitDateAddName, List(IntervalExpr(n, u), rec(d)))
      case DateDiff(u, s, e) =>
        FunSqlExpr("datediff", List(Verbatim(u.toString.toLowerCase), rec(s), rec(e)))
      case Funcall(name, db, ns, args, _) =>
        FunSqlExpr(emitter emitProcedureName (name, ns) run,
                   args map rec)
      case Windowed(agg, over) =>
        OverSqlExpr(compileAggFunc(agg, lookupColumn), compileWindow(over, lookupColumn))
      case BuiltinCall(b,args) => FunSqlExpr(compileBuiltin(b), args.map(rec))
      case Cast(o, ty) => CastSqlExpr(rec(o), ty)
    }
    rec(op)
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
    case Avg(x) => FunSqlExpr("AVG", List(compileOp(x, attrs)))
    case Min(x) => FunSqlExpr("MIN", List(compileOp(x, attrs)))
    case Max(x) => FunSqlExpr("MAX", List(compileOp(x, attrs)))
    /** @todo MSP - SQLite does not support STDDEV or VAR, work around somehow? */
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

  /** Compile a `predicate`, delegating column reference expression
    * compilation to `lookupColumn`.
    */
  def compilePredicate(predicate: Predicate,
                       lookupColumn: String => SqlExpr)(
                       implicit emitter: SqlEmitter): SqlPredicate = {
    def subop(op: Op) = compileOp(op, lookupColumn)
    predicate.apply[SqlPredicate](
      atom = b => SqlTruth(b),
      lt = (s1, s2) => SqlLt(subop(s1), subop(s2)),
      gt = (s1, s2) => SqlGt(subop(s1), subop(s2)),
      eq = (s1, s2) => SqlEq(subop(s1), subop(s2)),
      not = e => SqlNot(e),
      or = SqlOr(_, _),
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

  /** Execute `p` statements, returning the list of `TableName`s that were
    * created.
    */
  def sequenceSql(p : List[SqlStatement])(implicit memoLookup : HashSet[TableName]): DB[List[TableName]] = p.distinct.traverse {
    case SqlLoad(tn, h, pc) => bulkLoad(h, tn, pc) as List()
    case SqlCreateIfNotExists(tn,pre,create,stats) =>
      if(memoLookup.contains(tn))
          List().point[DB]
          else {
            memoLookup += tn
            val tecol = "tableExists"
            val (sql, errorMeansExists) = emitter.checkExists(tn, tecol)
            logger ltrace ("Executing sql: " + sql.run)
            DB.transaction(withResultSet(sql, rs => {
              rs.next() && (rs.getObject(tecol) ne null)
            }.point[DB]).flatMap(b =>
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
      logger ltrace ("Executing sql: " + sql.run)
      DB.executeUpdate(sql) as {
        x match {case sc: SqlCreate => List(sc.table)
                 case _ => List()}
      }
  }.map{_.flatten}

  private[this]
  def cleanTempTables(ts: List[TableName]): DB[Unit] =
    emitter.emitDropTempTable
      .map{dtt => ts.traverse_ {
             case tn@TableName(_, _, TableName.Temporary) =>
               val sql = dtt(tn)
               logger ltrace ("Executing sql: " + sql.run)
               DB.executeUpdate(sql)
             case _ => ().point[DB]
           }}
      .getOrElse(().point[DB])

  def scanMem[A:Monoid](m: Mem[Nothing, Nothing],
                        f: Process[Record, A],
                        order: List[(String, SortOrder)] = List()): DB[A] = {
    implicit val sup = Supply.create
    implicit val memoLookup = new HashSet[TableName]()
    implicit val scopeBuilder = List()
    compileMem(Optimizer.optimize(m), (x:Nothing) => x, (x: Nothing) => x) match {
      case MemPrg(h, p, q, rx) => for {
        ts <- sequenceSql(p)
        a <- q(order) map (_ andThen f execute)
        _ <- cleanTempTables(ts)
      } yield a
    }
  }

  def scanRel[A:Monoid](m: Relation[Nothing, Nothing],
                        f: Process[Record, A],
                        order: List[(String, SortOrder)] = List()): DB[A] = {
    implicit val sup = Supply.create
    implicit val memoLookup = new HashSet[TableName]()
    implicit val scopeBuilder = List()
    compileRel(Optimizer.optimize(m), (x:Nothing) => x, (x: Nothing) => x) match {
      case SqlPrg(p, ns, q, rx) => for {
        ts <- sequenceSql(p)
        a <- scanAndUniq(q, order, ns) map (_ andThen f execute)
        _ <- cleanTempTables(ts)
      } yield a
    }
  }

  override def dumpRel(m: Relation[Nothing, Nothing],
                       order: List[(String, SortOrder)] = List()): String = {
    implicit val sup = Supply.create
    implicit val memoLookup = new HashSet[TableName]()
    implicit val scopeBuilder = List()
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

  def compileMem[M,R](m: Mem[R, M], smv: M => MemPrg, srv: R => SqlPrg)(implicit sup: Supply, memoLookup: HashSet[TableName], scopeBuilder : List[() => String]): MemPrg =
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
        val MemPrg(h, ps, q, rx) = compileMem(e, smv, srv)
        MemPrg(Map(attr.name -> attr.t),
               ps,
               _ => q(List()) map (_ andThen reduceProcess(op, attr.t).outmap(p => RecordMap(attr.name -> p))),
               ForallTups(Map(attr.name -> None), PartitionedSet.zero))
      case LimitM(m, start, stop, order) =>
        val MemPrg(h, ps, q, rx) = compileMem(m, smv, srv)
        val start2 = start.getOrElse(0)
        val drop = start.map( Process.dropping[Record](_) )
        val take = stop.map( stop2 => Process.taking[Record]( stop2 - start2) )
        MemPrg( h,
                ps,  // todo: do this less ugly-ily
                o => q(order) map {proc => val dropped = drop.map( proc andThen _ ).getOrElse(proc)
                                           take.map( dropped andThen _ ).getOrElse(dropped)
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
          val ord: Order[Record] = recordOrd(preo)
          val merged = ^(q1(preo), q2(preo))(
            (q1p, q2p) => q1p.tee(q2p)(Tee.mergeOuterJoin((r: Record) => r filterKeys jk,
                                                          (r: Record) => r filterKeys jk
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
              // and it doesn't make sense to add orphans to descendantLeaves
              tree.get(parentId) foreach { parent =>
                descendantLeaves = descendantLeaves + (parentId -> (descendantLeaves(parentId) :+ leaf))
                val grandParentId = parent(parentIdCol.name)
                if( tree.contains(grandParentId) ) // Are we at the root node yet?
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
        implicit def err(s: String, msgs: String*): Option[Nothing] = None
        val hdr = Typer.accumulateType[Option](
          parentIdCol.toHeader, nodeIdCol.toHeader,
          v => Typer.memTyper(Mem.instantiate(EmptyRel(v), expr).substPrg(srv andThen (_.q.h), smv andThen (_.h))).toOption,
          Typer.memTyper(l.substPrg(srv andThen (_.q.h),smv andThen (_.h))).toOption.get).get
        MemPrg(hdr, pt ++ pl, accumProc, rt.filterKeys((k:String) => k == nodeIdCol.name))
      case GroupByM(m, k, expr) =>
        def toOp(a: Attribute) = Op.ColumnValue(a.name, a.t)
        val MemPrg(h, p, q, r) = compileMem(m, smv, srv)
        val knames = k.map(_.name).toSet
        val joined: OrderedProcedure[DB, Record] = {
          (ord: List[(String, SortOrder)]) => (db: java.sql.Connection) =>
             val kord_ = ord.filter { p => knames.contains(p._1) }
             val kord = kord_ ++ (knames -- kord_.map(_._1)).map(n => (n, SortOrder.Asc))
             val v2ord = ord filterNot (kord_ contains)
             // this will actually run the outermost query, but this is prob
             // fine, since we are guarded by a function
             val rows: Procedure[scalaz.Id.Id, Record] = Mem.join { q(kord)(db).
               andThen(
                 Process.groupingBy((r: Record) => r.filterKeys(knames.contains))).
               map { case (key, recs) =>
                 val x = Literal(recs.head, recs.tail)
                 val subquery = Mem.instantiate(x, expr)
                 val MemPrg(sh, sp, sq, sr) = compileMem(subquery, smv, srv)
                 if (!sp.isEmpty)
                   sys.error("subqueries of groupBy cannot 'let' new temp tables: " + subquery)
                 else
                   sq(v2ord)(db).map(_ ++ key)
               }
             }
             rows andThen sorting(kord ++ v2ord, ord) andThen uniq(ord.map(_._1).toSet)
        }
        implicit def err(s: String, msgs: String*): Option[Nothing] = None
        val hdr = Typer.groupByType[Option](
          h, k.map(_.tuple).toMap,
          v => Typer.memTyper(Mem.instantiate(EmptyRel(v), expr).substPrg(srv andThen (_.q.h), smv andThen (_.h))).toOption).get
        MemPrg(hdr, p, joined, r.filterKeys(knames.contains))
      case ProcedureCall(args, h, proc, namespace)  => sys.error("TODO")
      case l@Literal(t,ts) =>
        def src(rs: Stream[Record]): com.clarifi.machines.Source[Record] = rs match {
          case r #:: rs => Emit(r, () => src(rs))
          case _       => Stop
        }
        MemPrg(l.header, List(),
          so => procedureFromSource(src(l.mapCollections( xs => sort(xs, so), xs => sort(xs, so)).toStream)).point[DB],
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
        val mapRecord = (ops: Map[Attribute, Op]) => (proc:Procedure[scalaz.Id.Id, Record]) => proc.map((t: Record) => ops.map { case (attr, op) => attr.name -> op.eval(t) })

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
        implicit def iderr(x: String, xs: String*) = sys.error((x::xs.toList).mkString("\n"))
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

  private def pivot(
    pKey: Set[ColumnName],
    pVals: Set[ColumnName],
    colMap: Map[ColumnName, (Record, Op, PrimExpr)],
    outer: Boolean
  ): Process[Record, Record] = {
    def collect(acc: Record, extra: Record): Process[Record, Record] =
      await[Record] flatMap { (r:Record) =>
        val nextra = r -- pKey -- pVals
        if (nextra == extra) { // we're on the same pivot row
          val kr = r filterKeys pKey
          val vr = r filterKeys pVals
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
      val kr = r filterKeys pKey
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

  def compileMerge[R,M](m1: Mem[R,M], m2: Mem[R,M],  smv: M => MemPrg, srv: R => SqlPrg, merge: Order[Record] => Tee[Record, Record, Record])(implicit sup: Supply, memoLookup: HashSet[TableName], scopeBuilder : List[() => String]) = {
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

  private def hashJoin(q1: DB[Procedure[Id, Record]], q2: DB[Procedure[Id, Record]], jk: Set[String]) =
    ^(q1, q2)((q1, q2) => q1.tee(q2)(Tee.hashJoin(_ filterKeys jk, _ filterKeys jk)).map(p => p._1 ++ p._2))

  private def leftHashJoin(dq1: DB[Procedure[Id, Record]],
                           dq2: DB[Procedure[Id, Record]],
                           jk: Set[String],
                           nulls: Record): DB[Procedure[Id, Record]] = {
    def build(m: Map[Record, Vector[Record]]): Plan[T[Record, Record], Nothing, Map[Record, Vector[Record]]] =
      awaits(right[Record]) flatMap { rr =>
        val k = rr filterKeys jk
        build(m.updated(k, m.getOrElse(k, Vector.empty) :+ rr))
      } orElse Return(m)
    def augments(m: Map[Record, Vector[Record]], r: Record): Vector[Record] = m.lift(r filterKeys jk) match {
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

    /** @todo SMRC Since this was written, the op language has changed
      *       such that this answers true too often.
      */
    def columnDistinctness(rx: Reflexivity[ColumnName], op: Op, col: ColumnName): Boolean = {
      val ms = op.foldMap((c: ColumnName) => Map(c -> 1))
      ms.get(col).map(_ == 1).getOrElse(false) && ms.keySet.forall(c => c == col || rx.consts.isDefinedAt(c))
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
                      , scopeBuilder: List[() => String]
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

        // Limiting to one row or less necessarily makes all things constant
        val nrx = (from, to) match {
          case (Some(f), Some(t)) if t-f < 2 =>
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
                                 fillTable(unt, iq.h, iq.q(true)._2)
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
        val create :: fillStat = fillTable(myTN, rc.q.h, rc.q.q(true)._2)
        val createWithKey = if (pk.isEmpty) {
                              create
                            } else {
                              create match {
                                case c: SqlCreate => c.copy(hints = c.hints.reorder(pk).withPK(SortedSet(pk: _*)))
                                case _ => sys.error("Panic: The impossible happened: create table statement was not a create table statement")
                              }
                            }
        val myPrg = List(SqlCreateIfNotExists(myTN, rc.prg, createWithKey, fillStat))
	SqlPrg(myPrg, List(), DistinctiveQuery.table(rc.q.h, myTN), rc.refl)
      }
      case LetR(ext, exp) =>
        val un = guidName
        val tn = TableName(un, List(), TableName.Temporary)
        val tup = ext match {
          case ExtRel(rel, _) => // TODO: Handle namespace
            val SqlPrg(ip, _, iq, rx) = compileRel(rel, smv, srv) // TODO: do something with notes
            (iq.h, rx, ip ++ fillTable(tn, iq.h, iq.q(true)._2))
          case ExtSM(sm) =>
            val (pop, h, rx) = sms(sm)
            (h, rx,
              List(SqlCreate(
                     table = tn, header = h),
                   SqlLoad(tn, h, pop(List()))))
          case ExtMem(mem) =>
            val m = compileMem(mem, smv, srv)
            val MemPrg(h, p, pop, rx) = m
            (h, rx,
              p ++ List(SqlCreate(table = tn, header = h),
                        SqlLoad(tn, h, pop(List()))))
        }
        val (ih, rx1, ps) = tup
        val SqlPrg(p, ns, q, rx2) = compileRel(exp, smv, (v: RLevel[M,R]) => v match {
          case RTop => SqlPrg(List(), List(), DistinctiveQuery.table(ih, tn), rx1)
          case RPop(e) => compileRel(e, smv, srv)
        })(sup, memoLookup, (() => ext.toString) :: scopeBuilder)
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

    def columns(h: Header, rv: TableName) = h.map(x => (x._1, ColumnSqlExpr(rv, x._1)))

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
      val src = SqlSubquery(q, h.keys.toList, un)
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

    def literal(l: SmallLit)(implicit sup: Supply): DistinctiveQuery = {
      DistinctiveQuery(l.header, _ => (true, LiteralSqlTable(l.tups.map(r => r.mapValues(x => SqlExpr.compileLiteral(x))))))
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

    import DistinctiveQuery.{satisfyDistinct, columns, asSelect, asOrderable}
    import emitter.distinctEagerly

    def union(other: DistinctiveQuery)(implicit sup: Supply): DistinctiveQuery =
      DistinctiveQuery(h, needDistinct =>
        (q(false), other.q(false)) match {
          case ((d1, q1), (d2, q2)) =>
            (true, SqlUnion(asOrderable(h,q1), asOrderable(h,q2)))
        })

    def minus(other: DistinctiveQuery)(implicit sup: Supply): DistinctiveQuery = {
      val ul = freshName
      val ur = freshName
      DistinctiveQuery(h, needDistinct =>
        (q(distinctEagerly), other.q(false)) match {
          case ((d, q1), (_, q2)) =>
            // No need for the thing we're subtracting to be distinct
            satisfyDistinct(d, needDistinct, h, SqlExcept(asOrderable(h, q1), TableName(ul), asOrderable(h, q2), TableName(ur), h))
        })
    }

    def squashLiteral(attrs: Map[SqlColumn, SqlExpr], h: Header, q: SqlQuery.Scannable with SqlQuery.Nestable, on: Set[(String,String)], mode: JoinMode)
                     (implicit sup: Supply): SqlSelect = {
      val v = asSelect(h,q)
      val preds = on.toList.map {
        case (l,r) => SqlEq(v.attrs(r),attrs(l))
      }
      if (v.isAggregated)
        v.copy(attrs = v.attrs ++ attrs,
               having = v.having ++ preds)
      else
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
                  val v1 = asSelect(h,q1, v => !v.isAggregated
                                            && !v.sources.sources.isEmpty
                                            && !v.isWindowed
                                            && (mode match {
                                                 case JoinMode.Right | JoinMode.Full => v.where.isEmpty
                                                 case _ => true
                                               }))
                  val v2 = asSelect(other.h,q2, v => !v.isAggregated
                                                  && !v.sources.sources.isEmpty
                                                  && !v.isWindowed
                                                  && (mode match {
                                                       case JoinMode.Left | JoinMode.Full => v.where.isEmpty
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
          DistinctiveQuery(other.h ++ h, nd => satisfyDistinct(d1 && d2, nd, other.h ++ h, q3))
        }
    }

    def filter(pred: Predicate)(implicit sup: Supply): DistinctiveQuery = {
      DistinctiveQuery(h, needDistinct => q(distinctEagerly) match {
        case (d, q) => satisfyDistinct(d, needDistinct, h, asSelect(h,q, v => !v.isWindowed) match {
          case v =>
            if (v.isAggregated)
              v.copy(having = compilePredicate(pred, v.attrs) :: v.having)
            else
              v.copy(where  = compilePredicate(pred, v.attrs) :: v.where )
        })
      })
    }

    def aggregate(attr: Attribute, f: AggFunc)(implicit sup: Supply): DistinctiveQuery = {
      DistinctiveQuery(Map(attr.name -> attr.t), _ => q(true) match {
        case (_, q) => (true, {
          val v = asSelect(h, q, x => !x.isAggregated && !x.options("distinct") && !x.isWindowed)
          v.copy(attrs = Map(attr.name -> compileAggFunc(f, v.attrs)),
                 isAggregated = true)
        })
      })
    }

    def aggregateByGroup(cs: Map[Attribute,Op],
                         aggs: List[(Attribute,AggFunc)],
                         group: List[Op.ColumnValue]
                        )(implicit sup: Supply): DistinctiveQuery = {
      val (_, sq) = q(true) // to aggregate, we need distinctness
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

    def project(cols: Map[Attribute,Op], rx: Reflexivity[ColumnName])(implicit sup: Supply): DistinctiveQuery = {
      val resultHeader = cols.map(_._1.tuple)
      val preservesDistinct = preservesDistinctness(h, rx, cols)
      DistinctiveQuery(resultHeader, needDistinct => q(preservesDistinct && distinctEagerly) match {
        case (d, q) =>
          val q2 = asSelect(h,q) match {
            case v => v.copy(attrs = selectOps(cols, v.attrs),
                             windowColumns = selectWindows(cols, v.windowColumns))
          }
          satisfyDistinct(d && preservesDistinct, needDistinct, resultHeader, q2)
      })
    }

    def rename(attr: Attribute, to: ColumnName)(implicit sup: Supply): DistinctiveQuery = {
      val resultHeader = h - attr.name + (to -> attr.t)
      DistinctiveQuery(resultHeader, distinct => q(distinct) match {
        case (d, q) =>
          val q2 = asSelect(h,q)
          val nattrs = q2.attrs - attr.name + (to -> q2.attrs(attr.name))
          val nwinCs = if (q2.windowColumns.contains(attr.name))
                         q2.windowColumns - attr.name + to
                       else q2.windowColumns
          (d, q2.copy(attrs = nattrs, windowColumns = nwinCs))
      })
    }

    def except(cols: Set[ColumnName], rx: Reflexivity[ColumnName])(implicit sup: Supply): DistinctiveQuery = {
      val resultHeader = h -- cols
      val colOps = resultHeader map { case (c,t) => Attribute(c,t) -> Op.ColumnValue(c,t) }
      val preservesDistinct = preservesDistinctness(h, rx, colOps)
      DistinctiveQuery(resultHeader, needDistinct => q(preservesDistinct && distinctEagerly) match {
        case (d, q) =>
          val v = asSelect(h,q)
          val q2 = v.copy(attrs = v.attrs -- cols, windowColumns = v.windowColumns -- cols)
          satisfyDistinct(d && preservesDistinct, needDistinct, resultHeader, q2)
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
          val u1 = TableName(freshName)
          val u2 = TableName(freshName)
          DistinctiveQuery(h, needDistinct => q(!isOneRow) match {
            case (d, q) => 
              val actualOrder = if (!order.isEmpty) order
                                else h.map { case (k,t) => (k, SortOrder.Asc) }.toList
              satisfyDistinct(d || isOneRow, needDistinct, h, emitter.implementLimit(asOrderable(h,q), h, u1, from, to, actualOrder.map {
                case (k, v) => (k, v(asc = SqlAsc, desc = SqlDesc))
              }, u2))
        })
      }
    }

    def pivot(key: Set[ColumnName], vals: Set[ColumnName], outer: Boolean, colMap: Map[ColumnName, (Record, Op, PrimExpr)])(implicit sup: Supply): DistinctiveQuery = {
      implicit def iderr(x: String, xs: String*) = sys.error((x::xs.toList).mkString("\n"))
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
