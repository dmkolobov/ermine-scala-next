package com.clarifi.reporting
package relational

import sql._
import Op._

import scalaz._
import Scalaz._
import std.map.mapKeys
//import syntax.monad._
//import syntax.monoid._
//import syntax.equal._
//import Equal._

//import std.vector._

import com.clarifi.machines._

object Optimizer {
  private type JoinKey = Set[SqlColumn]

  private[this] implicit val boteq = Equal.equalA[Nothing]

  // The largest size for a literal to be considered small enough to turn into a predicate.
  private val smallLitSize = 30

  def optimize(mem: Mem[Nothing, Nothing]): Mem[Nothing, Nothing] = {
    TrivialAugment.detrivialize(optimizeMem[Nothing, Nothing](mem, x => x, x => x)._3)
  }

  def optimize(rel: Relation[Nothing, Nothing]): Relation[Nothing, Nothing] = {
    val (h, optr) = optimizeRel[Nothing, Nothing](rel, x => x, x => x)
    optr
  }

  def optimize(ext: Ext[Nothing, Nothing]): Ext[Nothing, Nothing] = {
    optimizeExt[Nothing, Nothing](ext, x => x, x => x)._2
  }

  def optimizeExt[M: Equal, R: Equal](ext: Ext[M, R],
                                      hr: R => Header,
                                      hm: M => Header): (Header, Ext[M, R]) = ext match {
    case ExtMem(e) =>
      val (h, _, optm) = optimizeMem(e, hr, hm)
      (h, ExtMem(TrivialAugment.detrivialize(optm)))
    case ExtRel(r, ns) =>
      val (h, r2) = optimizeRel(r, hr, hm)
      (h, ExtRel(r2, ns))
    case ExtSM(sm) => (sm.header, ext)
  }

  private[Optimizer] def optimizeHashJoin[R, M](h1: Header, uh1: Header, aug1: AugmentSM[R, M],
                                                h2: Header, uh2: Header, aug2: AugmentSM[R, M]):
                           (Header, Header, AugmentSM[R, M]) = (aug1, aug2) match {
    case (TrivialAugment(EmbedMem(ExtSM(sm))), _) => (h1 ++ h2, uh2, augmentMore(aug2, sm))
    case (_, TrivialAugment(EmbedMem(ExtSM(sm)))) => (h1 ++ h2, uh1, augmentMore(aug1, sm))
    case (AugmentSM(main1, cur1, hist1), AugmentSM(main2, cur2, hist2)) =>
      (h1 ++ h2, uh1 ++ uh2, AugmentSM(HashInnerJoin(main1, main2), cur1 ++ cur2, hist1 ++ hist2))
  }

  private[Optimizer] def augmentMore[R, M](aug: AugmentSM[R, M], sm: SM) = sm match {
    case LookupSM(f, a)     => aug copy (cur = aug.cur :+ (f -> a))
    case HistoricalSM(f, a) => aug copy (hist = aug.hist :+ (f -> a))
  }

  // mem: thing we want to optimize
  // these are needed for certain optimizations:
  //   hr: tells us the header type for each relational variable
  //   hm: tells us the header type for each mem variable
  // returns: (overall header of result, header _before_ adding SM columns, optimized mem)
  private[Optimizer] def optimizeMem[R: Equal, M: Equal](mem: Mem[R, M],
                                                         hr: R => Header,
                                                         hm: M => Header): (Header, Header, AugmentSM[R, M]) = {
    import TrivialAugment.detrivialize
    import PrimT.{StringT, DateT}

    def rec(mem: Mem[R, M]) = optimizeMem(mem, hr, hm)
    def flatProjectM(m: Mem[R, M], cs: Projection): Mem[R, M] = m match {
      case ProjectM(im, ics) => ProjectM(im, flattenProjection(cs, ics))
      case m => ProjectM(m, cs)
    }
    def smField(cur: List[(String, String)], hist: List[(String, String)], field: String) =
      if(cur.isEmpty && hist.isEmpty) false
      else {
        cur.exists(_._1 == field) ||
        hist.exists(_._1 == field) ||
        (hist.nonEmpty && field == "date") ||
        field == "issueId"
      }

    mem match {
      case VarM(v) => (hm(v), hm(v), TrivialAugment(VarM(v)))
      case AugmentSM(main, cur, hist) =>
        implicit def iderr(x: String, xs: String*) = sys.error((x::xs.toList).mkString("\n"))
        val h = Typer.memTyperAux[Id, R, M](main, hr, hm)
        val nh = Typer.augmentType(h, cur, hist)
        (nh, h, AugmentSM(main, cur, hist))
      case LetM(e, expr) => e match {
        case sm : ExtSM => optimizeMem(Mem.instantiate(EmbedMem(sm), expr): Mem[R,M], hr, hm)
        case ExtRel(r, db) => optimizeRel(r, hr, hm) match {
          case (h, optr) =>
            val (eh, _, optexpr) = optimizeMem[R, Option[M]](Mem.fromScope(expr), hr, {
                                     case None => h
                                     case Some(ep) => hm(ep)
                                   })
            (eh, eh, TrivialAugment(LetM(ExtRel(optr, db), Mem.toScope(detrivialize(optexpr)))))
        }
        case ExtMem(m) => val (h1, _, oe) = rec(m)
                          val (h2, _, oexpr) = optimizeMem[R, Option[M]](Mem.fromScope(expr)
                                                                        , hr
                                                                        , {case None => h1
                                                                           case Some(ep) => hm(ep)})
                          (h2, h2, TrivialAugment(LetM( ExtMem(detrivialize(oe)), Mem.toScope(detrivialize(oexpr)) )))
      }
      case ProcessM(f, m) =>
        val (h, uh, m2) = rec(m)
        val oh = f.outputType(h)
        (oh, oh, TrivialAugment(ProcessM(f, detrivialize(m2))))
      case GroupByM(m, key, expr) =>
        val (h, uh, m2) = rec(m)
        val (eh, _, optexpr) = optimizeMem[R, Option[M]](Mem.fromScope(expr), hr, {
          case None => h -- key.map(_.name)
          case Some(ep) => hm(ep)
        })
        val eh2 = eh ++ key.map(_.tuple)
        (eh2, eh2, TrivialAugment(GroupByM(detrivialize(m2), key, Mem.toScope(detrivialize(optexpr)))))
      case AccumulateM(parentIdCol, nodeIdCol, expr, leaves, tree) =>
        val (h, uh, m2) = rec(leaves)
        val (ht, uht, m2t) = rec(tree)
        val (eh, _, optexpr) = optimizeMem[R, Option[M]](Mem.fromScope(expr), hr, {
          case None => h - nodeIdCol.name
          case Some(ep) => hm(ep)
        })
        val eh2 = eh + nodeIdCol.tuple
        (eh2, eh2, TrivialAugment(AccumulateM(
          parentIdCol, nodeIdCol, Mem.toScope(detrivialize(optexpr)),
          detrivialize(m2), detrivialize(m2t))))
      case LimitM(m, start, end, order) =>
        var (h, uh, optm) = optimizeMem(m, hr, hm)
        optm match {
          case AugmentSM(main, cur, hist) => (h, uh, AugmentSM( LimitM(main, start, end, order), cur, hist ))
          case _ => (h, h, TrivialAugment(LimitM(detrivialize(optm), start, end, order)))
        }
      case FilterM(m, p) =>
        var (h, uh, optm) = optimizeMem(m, hr, hm)
        optm match {
          case AugmentSM(main, cur, hist) if p.columnReferences.forall(uh.contains(_)) =>
            (h, uh, AugmentSM(FilterM(main, p), cur, hist))
          case _ => (h, h, TrivialAugment(FilterM(detrivialize(optm), p)))
        }
      case ProjectM(m, cs) =>
        val (h, uh, m2) = rec(m)
        val nh = cs map (_._1.tuple)
        (nh, nh, TrivialAugment(flatProjectM(detrivialize(m2), cs)))
      case CombineM(m, c, op) =>
        val (h, uh, optm) = rec(m)
        optm match {
          case AugmentSM(main, cur, hist) if op.columnReferences.forall(uh.contains(_)) =>
            (h + c.tuple, uh + c.tuple, AugmentSM(flatProjectM(main, Header.proj(uh) + (c -> op)), cur, hist))
          case _ =>
            (h + c.tuple, h + c.tuple, TrivialAugment(flatProjectM(detrivialize(optm), Header.proj(h) + (c -> op))))
        }
      case ExceptM(m, cs) =>
        val (h, uh, optm) = rec(m)
        val nh = h -- cs
        (nh, nh, TrivialAugment(ExceptM(detrivialize(optm), cs)))
      case RenameM(m, attr, c, b) =>
        val (h, uh, optm@AugmentSM(main, cur, hist)) = rec(m)
        val newType = if(b) attr.t.withNull else attr.t
        val newAttr = Attribute(c, newType)
        val h2 = h + (c -> newType) - attr.name
        val uh2 = uh + (c -> newType) - attr.name

        if (smField(cur, hist, attr.name)) { // we're renaming an SM column, so we can't move under
          val smCols = Header.proj(h2) + (newAttr -> Op.ColumnValue(attr.name, newType))
          (h2, h2, TrivialAugment(
                     ProjectM(detrivialize(optm),
                              smCols)))
                              }
        else {
          (h2, uh2, AugmentSM(
                      flatProjectM(
                        main,
                        Header.proj(uh2) + (newAttr -> Op.ColumnValue(attr.name, newType))),
                      cur, hist))
                      }
      case AggregateM(m, c, op) =>
        val (_, _, optm) = rec(m)
        (Map(c.tuple), Map(c.tuple), TrivialAugment(AggregateM(detrivialize(optm), c, op)))
      case MergeOuterJoin(m1, m2) =>
        val (h1, _, om1) = rec(m1)
        val (h2, _, om2) = rec(m2)
        val ch = h1 ++ h2
        (ch, ch, TrivialAugment(MergeOuterJoin(detrivialize(om1), detrivialize(om2))))
      case HashInnerJoin(m1, m2) =>
        val (h1, uh1, om1) = rec(m1)
        val (h2, uh2, om2) = rec(m2)
        optimizeHashJoin(h1, uh1, om1, h2, uh2, om2)
      case HashLeftJoin(inner, outer) =>
        val (h1, _, oinner) = rec(inner)
        val (h2, _, oouter) = rec(outer)
        val ch = h1 ++ h2
        (ch, ch, TrivialAugment(HashLeftJoin(detrivialize(oinner), detrivialize(oouter))))
      case UnionM(m1, m2) =>
        val (h1, _, o1) = rec(m1)
        val (h2, _, o2) = rec(m2)
        val ch = h1 ++ h2
        (ch, ch, TrivialAugment(UnionM(detrivialize(o1), detrivialize(o2))))
      case Pivot(under, ks, vs, outer, km) =>
        val (hu, uhu, omu) = rec(under)
        implicit def err(s: String, ss: String*): Option[Nothing] = None
        val nh = Typer.pivotType[Option](hu, ks, vs, outer, km).get
        (nh, nh, TrivialAugment(Pivot(detrivialize(omu), ks, vs, outer, km)))
      case DifferenceM(m1, m2) =>
        val (h1, _, o1) = rec(m1)
        val (h2, _, o2) = rec(m2)
        val ch = h1 ++ h2
        (ch, ch, TrivialAugment(DifferenceM(detrivialize(o1), detrivialize(o2))))
      case EmbedMem(ext) => ext match {
        case ExtMem(m) => rec(m)
        case ExtRel(r, db) => optimizeRel(r, hr, hm) match {
          case (h, e) => (h, h, TrivialAugment(EmbedMem(ExtRel(e, db))))
        }
        case ExtSM(sm) => (sm.header, sm.header, TrivialAugment(EmbedMem(ext)))
      }
      case QuoteMem(token) => sys.error("Panic: the optimizer found a QuoteMem: " + token)
      case MemoMem(m) =>
        val (h, _, m2) = optimizeMem(m, hr, hm)
        (h, h, TrivialAugment(MemoMem(m2)))
      case x : HardMem =>
        implicit def iderr(x: String, xs: String*) = sys.error((x::xs.toList).mkString("\n"))
        val h = Typer.memTyperAux[Id, R, M](x, hr, hm)
        (h, h, TrivialAugment(x))
    }
  }

  /** Rewrite `outer` to operate in `inner`'s context. */
  private def flattenProjection(outer: Projection, inner: Projection): Projection = {
    lazy val inline = cvAttr(inner)
    outer.transform{case (_, v) => v.postReplace[Id](inline)}
  }

  // Replaces the column references in the keys with column-valued ops.
  def cvAttr(m: Projection): Op => Op =
    mapKeys(m) { case Attribute(k, v) => Op.ColumnValue(k, v):Op } withDefault (x => x)

  /** Convert `litrel` to a predicate that works in the context of a
    * natural join.  This is not a `Relation` isomorphism, so cannot
    * be done generally; it is only safe to elide pure literal
    * relations into a containing Amalgamation with _other_ relations.
    */
  private def literalAsPredicate(litrel: NonEmptyList[Record]): Predicate =
    Predicates.any(litrel.map(Predicate.fromRecord).list)

  private def literalAsCases(jk: Set[ColumnName], litrel: NonEmptyList[Record]): Map[Attribute, Op] = {
    val preds = litrel.map(_ filterKeys jk).map(Predicate.fromRecord)
    (litrel.head.keySet -- jk).map {
      n => Attribute(n, litrel.head(n).typ) -> ((preds zip litrel).foldRight(None : Option[Op]) {
        case ((a, b), Some(r)) => Some(If(a, OpLiteral(b(n)), r))
        case ((a, b), None) => Some(OpLiteral(b(n)))
      }).get
    } toMap
  }

  def collectJoin[M, R](rel: Relation[M, R]): List[Relation[M, R]] = rel match {
    case Join(l, r) => collectJoin(l) ++ collectJoin(r)
    case _          => List(rel)
  }

  def joinLiterals(jk: Set[String], ts1: List[Record], ts2: List[Record]): List[Record] =
    Tee.hashJoin[Record, Record, Record](_ filterKeys jk, _ filterKeys jk).
      capL(com.clarifi.machines.Source(ts1)).cap(com.clarifi.machines.Source(ts2)).foldMap {
        case (x, y) => Vector(x ++ y)
      }.toList

  def renameAggregate[M, R](from: ColumnName, to: ColumnName, agg: AggregateByGroup[M,R]): AggregateByGroup[M, R] = agg match {
    case AggregateByGroup(under, cs, aggs, group) =>
      val newCs = cs.mapKeys {
        case Attribute(n, t) if from == n => Attribute(to, t)
        case attr => attr
      }
      val newAggs = aggs.map {
        case (Attribute(n, t), fun) if from == n => (Attribute(to, t), fun)
        case v => v
      }
      AggregateByGroup(under, newCs, newAggs, group)
  }

  // Determines if a set of projections is a simple renaming of columns.
  def simpleProject(proj: Map[Attribute, Op]): Option[Map[Attribute, ColumnValue]] =
    proj.toList.traverse[Option,(Attribute, ColumnValue)] {
      case (to, op) => op match {
        case from : ColumnValue => Some(to -> from)
        case _ => None
      }
    }.map(_.toMap)

  def projectAggregate[M, R](agg: AggregateByGroup[M, R], proj: Map[Attribute, ColumnValue]) = agg match {
    case AggregateByGroup(under, cs, aggs, group) =>
      val (ncp, nap) = proj.partition {
        case (attr, ColumnValue(nm, _)) => cs.exists{case (Attribute(anm,_), _) => anm == nm }
      }
      val aggmap = aggs.map{ case (attr,aggf) => attr.name -> aggf }.toMap
      val naggs = nap.mapValues((cv: ColumnValue) => aggmap(cv.col)).toList
      AggregateByGroup(under, flattenProjection(ncp,cs), naggs, group)
  }

  def exceptAggregate[M, R](agg: AggregateByGroup[M, R], exc: Set[ColumnName]) = agg match {
    case AggregateByGroup(under, cs, aggs, group) =>
      AggregateByGroup(under, cs.filterKeys(k => !exc(k.name)), aggs.filter(v => !exc(v._1.name)), group)
  }

  def optimizeRel[M: Equal, R: Equal](rel: Relation[M, R],
                                      hr: R => Header,
                                      hm: M => Header): (Header, Relation[M, R]) = rel match {
    case VarR(x) =>
      (hr(x), rel)
    case JoinOn(r1, r2, cols, mode) =>
      val (orh1, rl) = optimizeRel(r1, hr, hm)
      val (orh2, rr) = optimizeRel(r2, hr, hm)
      val h = orh2 ++ orh1
      (h, JoinOn(rl, rr, cols, mode))
    case Union(r1, r2) =>
      val (h, rl) = optimizeRel(r1, hr, hm)
      val (_, rr) = optimizeRel(r2, hr, hm)
      (h, Union(rl, rr))
    case MinusI(r1, r2) =>
      val (h, rl) = optimizeRel(r1, hr, hm)
      val (_, rr) = optimizeRel(r2, hr, hm)
      (h, Minus(rl, rr))
    case Filter(r, p) =>
      val (h, ir) = optimizeRel(r, hr, hm)
      (h, Filter(ir, p))
    case Project(r, cs) =>
      val (h, ir) = optimizeRel(r, hr, hm)
      val nh = cs.map(_._1.tuple)
      (nh, Project(ir, cs))
    case Except(r, cs) =>
      val (h, ir) = optimizeRel(r, hr, hm)
      (h -- cs, Except(ir, cs))
    case Combine(r, attr, op) =>
      val (h, ir) = optimizeRel(r, hr, hm)
      (h + attr.tuple, Combine(ir, attr, op))
    case RenameR(r, Attribute(from, ft), to) =>
      val (h, ir) = optimizeRel(r, hr, hm)
      val nh = h mapKeys {
        case col if col == from => to
        case col => col
      }
      (nh, RenameR(ir, Attribute(from, ft), to))
    case Limit(r, start, end, ord) =>
      val (h, ir) = optimizeRel(r, hr, hm)
      (h, Limit(ir, start, end, ord))
    case AggregateByGroup(r, cs, aggs, grp) =>
      val (_, ir) = optimizeRel(r, hr, hm)
      val h = (aggs.map(_._1.tuple).toMap ++ cs.keySet.map(_.tuple))
      (h, AggregateByGroup(ir, cs, aggs, grp))
    case Aggregate(r, attr, aggfunc) =>
      val (_, ir) = optimizeRel(r, hr, hm)
      val h = Map(attr.tuple)
      (h, Aggregate(ir, attr, aggfunc))
    case PivotR(r, key, vals, outer, keyMap) =>
      val (h, ir) = optimizeRel(r, hr, hm)
      implicit def iderr(x: String, xs: String*) = sys.error((x::xs.toList).mkString("\n"))
      val h2 = Typer.pivotType[Id](h, key, vals, outer, keyMap)
      (h2, PivotR(ir, key, vals, outer, keyMap))
    case LetR(r, e) =>
      r match {
        case ExtMem(l@Literal(t,ts)) if ts.length <= smallLitSize =>
          optimizeRel[M,R](Relation.instantiate(SmallLit( l.nel ), e), hr, hm)
        case _ =>  
          val (h, r2) = optimizeExt(r, hr, hm)
          val (h2, e2) = optimizeRel[M,Option[R]](Relation.fromScope(e), (r: Option[R]) => r match {
            case None => h
            case Some(x) => hr(x)
          }, hm)
          (h2, LetR(r2, Relation.toScope(e2)))
      }
    case MemoR(r, pk) =>
      val (h, r2) = optimizeRel(r, hr, hm)
      (h, MemoR(r2, pk))
    case TableProc(args, oh, fun, ns) =>
      val h = oh.toMap
      val oargs = TableProc.relFunctor(args)(ir => optimizeRel(ir, hr, hm)._2)
      (h, TableProc(oargs, oh, fun, ns))
    case Note(tags, under) =>
      val (h, r) = optimizeRel(under, hr, hm)
      (h, Note(tags, r))
    case r: HardRel =>
      implicit def iderr(x: String, xs: String*) = sys.error((x::xs.toList).mkString("\n"))
      val h = Typer.relTyperAux[Id, M, R](r, hr, hm)
      (h, r)
  }

  def headerOf[M, R](r: Relation[M, R], hr: R => Header, hm: M => Header): Header = {
    implicit def iderr(x: String, xs: String*) = sys.error((x::xs.toList).mkString("\n"))
    Typer.relTyperAux[Id, M, R](r, hr, hm)
  }

  private def reverseRename[K](m: Map[K, K]) =
    m map {_.swap} withDefault identity

  /**
   * Answer whether natural joins can be combined into a single `select`.
   * Rule 1: Every column in `joinKey` must appear as a ColumnValue reference in `prj1`
   * for which the `Attribute` key in prj1 also appears as a key in `prj2`.
   * Rule 2: For every key appearing in both `prj1` and `prj2`, the `Op` must be the same.
   */
  private def joinable(joinKey: JoinKey, prj1: Projection, prj2: Projection): Boolean =
    (joinKey forall { (k:ColumnName) => prj1.exists {
      case (a, ColumnValue(c, _)) => c == k && prj2.isDefinedAt(a)
      case _ => false
    }}) && ((prj1.keySet & prj2.keySet) forall { k => prj1(k) === prj2(k) })

}

object TrivialAugment {
  def apply[R, M](m: Mem[R, M]): AugmentSM[R, M] = AugmentSM(m, List(), List())
  def unapply[R, M](m: Mem[R, M]): Option[Mem[R, M]] = m match {
    case AugmentSM(m, List(), List()) => Some(m)
    case _                            => None
  }
  def detrivialize[R, M](m: Mem[R, M]): Mem[R, M] = m match {
    case TrivialAugment(m) => detrivialize(m)
    case _                 => m
  }
}
