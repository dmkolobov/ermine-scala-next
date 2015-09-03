package com.clarifi.reporting
package relational

import com.clarifi.reporting._
import com.clarifi.reporting.sql._
import com.clarifi.reporting.backends._
import com.clarifi.reporting.Reporting._
import com.clarifi.reporting.util.PartitionedSet
import DB._
import PrimT._
import ReportingUtils.simplifyPredicate
import SqlPredicate._
import SqlExpr.compileOp

import scalaz._
import scalaz.Coproduct._
import scalaz.IterV._
import Scalaz.{^ => _, toNel => _, _}
import scalaz.syntax.monad._
// important for instance resolution.
import scala.collection.immutable.IndexedSeq
import scalaz.std.indexedSeq.{toNel => _, _}
import scalaz.std.list._
import scalaz.std.vector.{toNel => _, _}
import scalaz.std.map._

import com.clarifi.machines._
import Plan.{ await, awaits, emit }
import Tee.{ right, left }

import org.apache.log4j.Logger
import com.clarifi.reporting.util.PimpedLogger._

class SqlScanner(sms: SMEnv[DB])(implicit emitter: SqlEmitter) extends Scanner[DB] {
  case class SqlPrg(prg: List[SqlStatement],
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

  // `attr`: The codomain attribute
  def compileAggFunc(attr: Attribute, f: AggFunc, attrs: String => SqlExpr): SqlExpr = f match {
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

  val exec = new SqlExecution()
  import exec._


  /** Execute `p` statements, returning the list of `TableName`s that were
    * created.
    */
  def sequenceSql(p : List[SqlStatement]): DB[List[TableName]] = p.distinct.traverse {
    case SqlLoad(tn, h, pc) => bulkLoad(h, tn, pc) as List()
    case SqlIfNotExists(tn,stats) => {
      val tecol = "tableExists"
      val sql = emitter.checkExists(tn, tecol)
      logger ltrace ("Executing sql: " + sql.run)
      catchException(DB.transaction(withResultSet(sql, rs => {
        rs.next() && (rs.getObject(tecol) ne null)
      }.point[DB]).flatMap(b => if (!b) sequenceSql(stats) else List().point[DB])))
      .map(_ fold (e => {logger error ("While executing: " + e.getMessage)
                        List()}, // drop them on the floor.
                   identity))
    }
    //TODO write job to clean out old memos
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
    compileRel(Optimizer.optimize(m), (x:Nothing) => x, (x: Nothing) => x) match {
      case SqlPrg(p, q, rx) => for {
	ts <- sequenceSql(p)
        a <- scanAndUniq(q, order) map (_ andThen f execute)
        _ <- cleanTempTables(ts)
      } yield a
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

  private
  def isBinaryColumn(h: Header, c: ColumnName) = h.get(c) match {
    case Some(_ : StringT) => true
    case _ => false
  }

  def orderQuery(h: Header, sql: SqlQuery, order: List[(String, SortOrder)])(implicit sup: Supply): SqlQuery = sql match {
    case sel : SqlSelect if sel.attrs.size > 0 && sel.limit == (None, None) =>
      sel copy (
        orderBy = order collect {
          case (col, ord) if (sel.attrs.get(col) map (_.deparenthesize) match {
             case None | Some(LitSqlExpr(_)) => false
             case Some(_) => true
          }) => (sel.attrs(col), ord(SqlAsc, SqlDesc), isBinaryColumn(h, col))
        }
      )
    case _ if order.nonEmpty =>
      val s = freshName
      SqlSelect(
        tables = Map(TableName(s) -> sql),
        orderBy = order.map { case (col, ord) =>
          (ColumnSqlExpr(TableName(s), col),
           ord(SqlAsc, SqlDesc),
           isBinaryColumn(h, col))
        }
      )
    case _ => sql
  }

  import SortOrder._
  import record.RecordMap

  private[this]
  def scanAndUniq(dq: DistinctiveQuery,
                  order: List[(String, SortOrder)])(implicit sup: Supply): DB[Procedure[Id, Record]] =
    dq.q(false) match {
      case (d, q) =>
        if (d) scanQuery(orderQuery(dq.h, q, order), dq.h) // already distinct
        else {
          val unsortedCols = dq.h.keySet -- order.map(_._1)
          val totalOrder = order ++ unsortedCols.toList.map(c => (c, Asc))
          scanQuery(orderQuery(dq.h, q, totalOrder), dq.h) map (_ andThen uniqSorted)
        }
    }

  def compileMem[M,R](m: Mem[R, M], smv: M => MemPrg, srv: R => SqlPrg)(implicit sup: Supply): MemPrg =
    m match {
      case VarM(v) => smv(v)
      case LetM(ext, expr) =>
        val p = compileMem( MemoMem(EmbedMem(ext)) , smv, srv )
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
        val SqlPrg(ps, q, rx) = compileRel(e, smv, srv)
        MemPrg(q.h, ps, o => scanAndUniq(q, o), rx)
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

        val needUniq = distinctness(h, rx, cs).exists(_ => true)

        def nq(so: List[(String, SortOrder)]) = {
          val nonOpOrder = so.filter( s => renamesStr.contains(s._1) )
          val so2 = nonOpOrder.map( {case (s,o) => (rename(s), o)} )
          q(so2) map { case proc =>
            val proc2 = mapRecord(cs)(proc) andThen sorting(nonOpOrder, so)
            if (needUniq) proc2 andThen uniq(so.map(_._1).toSet) else proc2
          }
        }

        MemPrg(cs.map(_._1.tuple), p, nq, combineAll(rx, cs))
      case Pivot(under, pKey, pVals, outer, keyMap) =>
        val MemPrg(h, p, q, rx) = compileMem(under, smv, srv)
        implicit def err(s: String, msgs: String*): Option[Nothing] = None
        val nh = Typer.pivotType[Option](h, pKey, pVals, outer, keyMap).get
        val nq: OrderedProcedure[DB, Record] = (ord:List[(ColumnName,SortOrder)]) => {
          val idCols = h.keySet -- pKey -- pVals
          val myOrd = idCols.toList.map(c => (c, Asc))
          q(myOrd) map { p =>
            val pp = p.andThen(pivot(pKey,pVals,keyMap,outer)).andThen(sorting(myOrd, ord))
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
    keyMap: Map[Record, (ColumnName, Op, PrimExpr)],
    outer: Boolean
  ): Process[Record, Record] = {
    val base : Record = if (outer) RecordMap(keyMap.values map { case (col,op,default) => col -> default })
                        else RecordMap()
    def collect(acc: Record, extra: Record): Process[Record, Record] =
      await[Record] flatMap { (r:Record) =>
        val nextra = r -- pKey -- pVals
        if (nextra == extra) { // we're on the same pivot row
          val kr = r filterKeys pKey
          val vr = r filterKeys pVals
          keyMap.get(kr) match {
            case None => collect(acc, extra)
            case Some((c, op, d)) => collect(acc + (c -> op.eval(vr)), extra)
          }
        } else {
          // TODO: check outer
          emit(extra ++ acc) flatMap { _ => prime(r) }
        }
      } orElse (emit(extra ++ acc) >> Stop)

    def prime(r: Record): Process[Record, Record] = {
      val extra = r -- pKey -- pVals
      val acc : Record = keyMap.get(r filterKeys pKey) match {
        case Some((c, op, default)) => base + (c -> op.eval(r))
        case None          => base
      }
      collect(acc, extra)
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

  def compileMerge[R,M](m1: Mem[R,M], m2: Mem[R,M],  smv: M => MemPrg, srv: R => SqlPrg, merge: Order[Record] => Tee[Record, Record, Record])(implicit sup: Supply) = {
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

  private def distinctness(h: Header, rx: Reflexivity[ColumnName], cols: Map[Attribute, Op]): Set[String] =
    rx match {
      case KnownEmpty() => Set()
      case ForallTups(_, _) =>
        if ((h.keySet diff rx.consts.keySet) forall (c =>
             cols exists {
               case (_, op) => preservesDistinctness(rx, op, c)
             })) Set() else Set("distinct")
    }

  /** @todo SMRC Since this was written, the op language has changed
    *       such that this answers true too often.
    */
  private def preservesDistinctness(rx: Reflexivity[ColumnName], op: Op, col: ColumnName): Boolean = {
    val ms = op.foldMap((c: ColumnName) => Map(c -> 1))
    ms.get(col).map(_ == 1).getOrElse(false) && ms.keySet.forall(c => c == col || rx.consts.isDefinedAt(c))
  }

  private def combineAll(rx: Reflexivity[ColumnName],
                         comb: Map[Attribute, Op],
                         keepOld: Boolean = false) =
    rx combineAll (mapKeys(comb)(_.name), {case x => x}, identity, keepOld)

  def compileRel[M,R](m: Relation[M, R],
                      smv: M => MemPrg,
                      srv: R => SqlPrg)(implicit sup: Supply): SqlPrg = {

    def columns(h: Header, rv: TableName) = h.map(x => (x._1, ColumnSqlExpr(rv, x._1)))

    def combineBinary(
      l: Relation[M, R],
      r: Relation[M,R],
      f: (DistinctiveQuery, DistinctiveQuery) => DistinctiveQuery,
      g: (Reflexivity[ColumnName], Reflexivity[ColumnName]) => Reflexivity[ColumnName]) = {
      val SqlPrg(p1, q1, refl1) = compileRel(l, smv, srv)
      val SqlPrg(p2, q2, refl2) = compileRel(r, smv, srv)
      SqlPrg(p1 ++ p2, f(q1, q2), g(refl1, refl2))
    }

    m match {
      case VarR(v) => srv(v)
      case Join(l, r) =>
        combineBinary(l, r, _ join _, _ && _)
      case JoinOn(l, r, on) =>
        combineBinary(l, r, _ joinOn (on, _), _ && _)
      case Union(l, r) =>
        combineBinary(l, r, _ union _, _ || _)
      case Minus(l, r) =>
        combineBinary(l, r, _ minus _, _ || _)
      case Filter(r, pred) =>
        val SqlPrg(p, q, rx) = compileRel(r, smv, srv)
        val pred1 = simplifyPredicate(pred, rx)
        SqlPrg(p, q.filter(pred1), filterRx(rx, pred))
      case Project(r, cols) =>
        val SqlPrg(p, q, rx) = compileRel(r, smv, srv)
        SqlPrg(p,
               q project (cols,rx),
               combineAll(rx, cols))
      case AggregateByGroup(r,cs,aggs,group) =>
        val SqlPrg(p, q, _) = compileRel(r, smv, srv)
        SqlPrg(p, q.aggregateByGroup(cs,aggs,group), ForallTups(aggs.map(_._1.name -> None).toMap, PartitionedSet.zero))
      case Aggregate(r, attr, f) =>
        val SqlPrg(p, q, _) = compileRel(r, smv, srv)
        SqlPrg(p, q.aggregate(attr, f), ForallTups(Map(attr.name -> None), PartitionedSet.zero))
      case Except(r, cs) =>
        val SqlPrg(p, q, rx) = compileRel(r, smv, srv)
        SqlPrg(p, q except cs, rx filterKeys (!cs.contains(_)))
      case Combine(r, attr, op) =>
        val SqlPrg(p, q, rx) = compileRel(r, smv, srv)
        SqlPrg(p, q combine (attr, op), combineAll(rx, Map(attr -> op), true))
      case Limit(r, from, to, order) =>
        val SqlPrg(p, q, rx) = compileRel(r, smv, srv)

        SqlPrg(p, q limit (from, to, order), rx)
      case Table(h, n) => SqlPrg(List(), DistinctiveQuery.table(h, n), Reflexivity.zero)
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
                               case (unt, SqlPrg(_, iq, _)) =>
                                 fillTable(unt, iq.h, iq.q(true)._2)
                             }, oh map (_._1),
                             argable map (_ bimap (_._1,
                                                   SqlExpr.compileLiteral)))
                 toList,
               DistinctiveQuery.table(h, sink),
               Reflexivity.zero)
      case RelEmpty(h) =>
        val un = guidName
        val n = TableName(un, List(), TableName.Temporary)
        SqlPrg(List(SqlCreate(table = TableName(un, List(), TableName.Temporary),
                              header = h)),
               DistinctiveQuery.table(h, n), KnownEmpty())
      case QuoteR(_) => sys.error("Cannot scan quotes")
      case l@SmallLit(ts) =>
        import com.clarifi.machines.Source
        val h = l.header
        val un = guidName
        val n = TableName(un, List(), TableName.Temporary)
        SqlPrg(List(SqlCreate(table = TableName(un, List(), TableName.Temporary),
                              header = h),
                    SqlLoad(TableName(un, List(), TableName.Temporary), h, procedureFromSource(Source.source(ts.toList)).point[DB])),
               DistinctiveQuery.table(h, n),
               Reflexivity literal ts)
      case MemoR(r) => {
	val rc = compileRel(r,smv,srv)
	val relHash = "MemoHash_" + r.##.toString
	val myTN = TableName(relHash, List(), TableName.Persistent)
	val fillStat = fillTable(myTN, rc.q.h, rc.q.q(true)._2)
	val myPrg = List(SqlIfNotExists(myTN,rc.prg ++ fillStat))
	SqlPrg(myPrg, DistinctiveQuery.table(rc.q.h, myTN), rc.refl)
      }
      case LetR(ext, exp) =>
        val un = guidName
        val tn = TableName(un, List(), TableName.Temporary)
        val tup = ext match {
          case ExtRel(rel, _) => // TODO: Handle namespace
            val SqlPrg(ip, iq, rx) = compileRel(rel, smv, srv)
            (iq.h, rx, ip ++ fillTable(tn, iq.h, iq.q(true)._2))
          case ExtSM(sm) =>
            val (pop, h, rx) = sms(sm)
            (h, rx, List(SqlCreate(
                           table = tn, header = h),
                         SqlLoad(tn, h, pop(List()))))
          case ExtMem(mem) =>
            val m = compileMem(mem, smv, srv)
            val MemPrg(h, p, pop, rx) = m
            (h, rx, p ++ List(SqlCreate(table = tn, header = h),
                              SqlLoad(tn, h, pop(List()))))
        }
        val (ih, rx1, ps) = tup
        val SqlPrg(p, q, rx2) = compileRel(exp, smv, (v: RLevel[M,R]) => v match {
          case RTop => SqlPrg(List(), DistinctiveQuery.table(ih, tn), rx1)
          case RPop(e) => compileRel(e, smv, srv)
        })
        SqlPrg(ps ++ p, q, rx2)
      case SelectR(rs, cs, where) =>
        // Here be dragons.
        val prgs = rs.map(compileRel(_, smv, srv))
        val (stmts, qs, rx) = prgs.foldRight((List[SqlStatement](),
                                              List[DistinctiveQuery](),
                                              Reflexivity.zero[ColumnName])) {
          case (SqlPrg(stmts, q, rx), (astmts, qs, rxs)) =>
            (stmts ++ astmts, q :: qs, rx && rxs)
          }
        val rx1 = filterRx(rx, where)
        val rx2 = combineAll(rx1, cs)
        SqlPrg(stmts, DistinctiveQuery.select(qs, cs, simplifyPredicate(where, rx), rx1), rx2)
      case RenameR(r, Attribute(from, ty), to) => sys.error("compiling unoptimized RenameR")
    }
  }

  object DistinctiveQuery {
    private[DistinctiveQuery]
    def satisfyDistinct(hasDistinct: Boolean, needDistinct: Boolean, q: SqlQuery)(implicit sup: Supply): (Boolean, SqlQuery) =
      if(hasDistinct || !needDistinct) (hasDistinct, q)
      else (true, q match {
        case sel : SqlSelect => sel copy (options = sel.options + "distinct")
        case _ =>
          SqlSelect(options = Set("distinct"),
                    attrs = Map(), // empty map = select *
                    tables = Map(TableName(freshName) -> q))
      })

    def table(h: Header, n: TableName): DistinctiveQuery =
      DistinctiveQuery(h, _ => (true, FromTable(n, h.keys.toList)))

    def select(
      dqs: List[DistinctiveQuery],
      cs: Map[Attribute,Op],
      where: Predicate,
      rx: Reflexivity[ColumnName]
    )(implicit sup: Supply): DistinctiveQuery = {
      val hs = dqs.map(_.h)
      val (ds, qs) = dqs.map(_.q(false)).unzip
      val subDistinct = ds.forall(b => b)
      val hsp = hs.map(h => freshName -> h)
      val columnLocs: Map[ColumnName, List[String]] =
        hsp.toIterable flatMap {
          case (subUn, h) => h.keys map (_ -> subUn)
        } groupBy (_._1) mapValues (_ map (_._2) toList)
      val lookupColumn = (c:ColumnName) => ColumnSqlExpr(TableName(columnLocs(c).head), c)
      val h = hs.foldRight(Map():Header)(_ ++ _)
      val distinctnessPreserved = distinctness(h, rx, cs).isEmpty
      val hasDistinct = subDistinct && distinctnessPreserved
      DistinctiveQuery(cs.map(_._1.tuple), needDistinct =>
        satisfyDistinct(hasDistinct, needDistinct,
          SqlSelect(attrs = cs.map {
                      case (attr, op) => attr.name -> compileOp(op, lookupColumn)
                    },
                    tables = (hsp zip qs) map {
                      case ((un, _), q) => TableName(un) -> q
                    } toMap,
                    criteria = compilePredicate(where,
                                                lookupColumn) :: (for {
                                 natJoin <- columnLocs
                                 val (colName, sources) = natJoin
                                 natJoinAtom <- sources zip sources.tail
                                 val (l, r) = natJoinAtom
                               } yield SqlEq(ColumnSqlExpr(TableName(l), colName),
                                             ColumnSqlExpr(TableName(r), colName))).toList)))
    }
  }

  case class DistinctiveQuery(h: Header, q: Boolean => (Boolean, SqlQuery)) {
    private[this] def guidName = "t" + sguid
    private[this] def freshName(implicit sup: Supply) = "t" + sup.fresh
    private[this] def columns(h: Header, rv: TableName) = h.map(x => (x._1, ColumnSqlExpr(rv, x._1)))

    import DistinctiveQuery.satisfyDistinct

    def union(other: DistinctiveQuery)(implicit sup: Supply): DistinctiveQuery =
      DistinctiveQuery(h, needDistinct =>
        (q(false), other.q(false)) match {
          case ((d1, q1), (d2, q2)) =>
            satisfyDistinct(false, needDistinct, SqlUnion(q1, q2))
        })

    def minus(other: DistinctiveQuery)(implicit sup: Supply): DistinctiveQuery = {
      val ul = freshName
      val ur = freshName
      DistinctiveQuery(h, needDistinct =>
        (q(false), other.q(false)) match {
          case ((d, q1), (_, q2)) =>
            // No need for the thing we're subtracting to be distinct
            satisfyDistinct(d, needDistinct, SqlExcept(q1, TableName(ul), q2, TableName(ur), h))
        })
    }

    def join(other: DistinctiveQuery)(implicit sup: Supply): DistinctiveQuery =
      DistinctiveQuery(h ++ other.h, needDistinct =>
        (q(false), other.q(false)) match {
          case ((d1, q1), (d2, q2)) =>
            satisfyDistinct(d1 && d2, needDistinct,
              (q1, q2) match {
                case (SqlJoin(xs, ul), SqlJoin(ys, _)) => SqlJoin(xs append ys, ul)
                case (SqlJoin(xs, ul), _) =>
                  SqlJoin(xs append NonEmptyList((q2, TableName(freshName), other.h)), ul)
                case (_, SqlJoin(ys, ur)) =>
                  SqlJoin((q1, TableName(freshName), this.h) <:: ys, ur)
                case (_, _) =>
                  val un = freshName
                  val ul = freshName
                  val ur = freshName
                  SqlJoin(NonEmptyList((q1, TableName(ul), this.h), (q2, TableName(ur), other.h)), TableName(un))
               })
    })

    def joinOn(on: Set[(String, String)], other: DistinctiveQuery)(implicit sup: Supply): DistinctiveQuery = {
      val un = freshName
      val ul = freshName
      val ur = freshName
      DistinctiveQuery(h ++ other.h, needDistinct =>
        (q(false), other.q(false)) match {
          case ((d1, q1), (d2, q2)) =>
            satisfyDistinct(d1 && d2, needDistinct,
              SqlJoinOn(
                (q1, TableName(ul), this.h),
                (q2, TableName(ur), other.h),
                on,
                TableName(un)))
        })
    }

    def filter(pred: Predicate)(implicit sup: Supply): DistinctiveQuery = {
      val un = freshName
      DistinctiveQuery(h, needDistinct => q(false) match {
        case (d, q) => satisfyDistinct(d, needDistinct, q match {
          case v:SqlSelect if (v.limit._1.isEmpty && v.limit._2.isEmpty) =>
            v.copy(criteria = compilePredicate(pred, v.attrs) :: v.criteria)
          case _ => SqlSelect(tables = Map(TableName(un) -> q),
                              attrs = columns(h, TableName(un)),
                              criteria = List(compilePredicate(pred, ColumnSqlExpr(TableName(un), _))))
        })
      })
    }

    def aggregate(attr: Attribute, f: AggFunc)(implicit sup: Supply): DistinctiveQuery = {
      val un = freshName
      DistinctiveQuery(Map(attr.name -> attr.t), _ => q(true) match {
        case (_, q) => (true, q match {
          case v:SqlSelect if v.limit == (None, None) && v.groupBy.isEmpty && !v.options("distinct") =>
            v.copy(attrs = Map(attr.name -> compileAggFunc(attr, f, v.attrs)))
          case _ => SqlSelect(tables = Map(TableName(un) -> q),
                              attrs = Map(attr.name -> compileAggFunc(attr, f, columns(h, TableName(un)))))
        })
      })
    }

    def aggregateByGroup(cs: Map[Attribute,Op],
                         aggs: List[(Attribute,AggFunc)],
                         group: List[Op.ColumnValue]
                        )(implicit sup: Supply): DistinctiveQuery = {
      val (_, sq) = q(true) // to aggregate, we need distinctness
      val un = freshName
      val groupByCols = columns(h, TableName(un))
      val groupBys = group map (compileOp(_, groupByCols))
      val plainCols = cs map { case (attr, op) =>
                        (attr.name -> compileOp(op, groupByCols)) }
      def subq =
        SqlSelect(tables = Map(TableName(un) -> sq),
                  attrs =  plainCols ++ aggs.map {
                             case (attr, f) =>
                               attr.name -> compileAggFunc(attr, f, columns(h, TableName(un)))
                           }.toMap,
                  groupBy = groupBys )
      val q2 = sq match {
        case v:SqlSelect if v.limit == (None, None) && !v.options("distinct") && v.groupBy.isEmpty =>
          // Note: this optimization relies on an assumption about aggregations to be correct.
          // Specifically, we don't want to coalesce two aggregations in sequence. There are two
          // checks that ensure this. First, we test to see if the underlying SqlSelect's groupBy
          // is empty. This ensures that it isn't an AggregateByGroup, or at least, not one that
          // isn't equivalent to an Aggregate. Second, backSubstituteSingle only works if the
          // groupBy we're optimizing only refers to pure columns in the underlying select's
          // tables. If it were an Aggregate, the only columns that exist are complex expressions,
          // so this will fail.
          //
          // The remaining case is two consecutive aggregations with no grouping. I think this will
          // produce bad SQL right now. But there's no reason to do it.
          groupBys.traverse[Option,SqlExpr] {
            case e =>
              SqlExpr.backSubstituteSingle(e, (_, col) => v.attrs(col))
          } match {
            case None => subq
            case Some(groupBysSubbed) =>
              val newAttrs = cs.map { case (attr, op) =>
                               attr.name -> compileOp(op, v.attrs)
                             } ++
                             aggs.map {
                               case (attr, f) =>
                                 attr.name -> compileAggFunc(attr, f, v.attrs)
                             }
              v.copy( attrs = newAttrs.toMap, groupBy = groupBysSubbed )
          }
        case _ => subq
      }
      DistinctiveQuery(cs.map(_._1.tuple) ++ aggs.map(_._1.tuple), _ => (true, q2))
    }

    def project(cols: Map[Attribute,Op], rx: Reflexivity[ColumnName])(implicit sup: Supply): DistinctiveQuery = {
      def compileCols(as: String => SqlExpr) =
        cols map { case (attr, op) =>
          (attr -> compileOp(op, as))
        }
      val un = freshName
      val as = columns(h, TableName(un))
      val ccols = cols map { case (attr, op) =>
        attr.name -> compileOp(op, as)
      }
      DistinctiveQuery(cols.map(_._1.tuple), needDistinct => q(false) match {
        case (d, q) =>
          val hasDistinct = d && distinctness(h, rx, cols).isEmpty
          satisfyDistinct(hasDistinct, needDistinct,
            SqlSelect(tables = Map(TableName(un) -> q), attrs = ccols))
      })
    }

    def except(cols: Set[ColumnName])(implicit sup: Supply): DistinctiveQuery = {
      val un = freshName
      DistinctiveQuery(h -- cols, distinct => q(distinct) match {
        case (d, q) => // todo: wrong
          (d, SqlSelect(tables = Map(TableName(un) -> q),
                        attrs = columns(h, TableName(un)) -- cols))
      })
    }

    def combine(attr: Attribute, op: Op)(implicit sup: Supply): DistinctiveQuery = {
      val un = freshName
      DistinctiveQuery(h + attr.tuple, distinct => q(distinct) match {
        case (d, q) =>
          (d, SqlSelect(tables = Map(TableName(un) -> q),
                attrs = {
                  val as = columns(h, TableName(un))
                  as + (attr.name -> compileOp(op, as))
                }))
      })
    }

    def limit(from: Option[Int], to: Option[Int], order: List[(String,SortOrder)])(implicit sup: Supply): DistinctiveQuery = {
        val u1 = freshName
        val u2 = freshName
        val (makeDistinct, ensuresDistinct) = (from, to) match {
          case (Some(i), Some(j)) => (j - i > 0, true)
          case (None, None) => (false, false)
          case _ => (true, true)
        }
        DistinctiveQuery(h, needDistinct => q(makeDistinct) match {
          case (d, q) =>
            satisfyDistinct(ensuresDistinct || d, needDistinct,
              emitter.emitLimit(q, h, TableName(u1), from, to, (toNel(order.map {
                case (k, v) =>
                  (ColumnSqlExpr(TableName(u1), k),
                   v.apply(
                     asc = SqlAsc,
                     desc = SqlDesc
                   ),
                   h(k).isInstanceOf[StringT]
                 )
              }).map(_.list).getOrElse(
                  h.map{ case (k,t) => (ColumnSqlExpr(TableName(u1), k), SqlAsc, t.isInstanceOf[StringT]) }.toList)), TableName(u2)))
        })
    }
  }
}
