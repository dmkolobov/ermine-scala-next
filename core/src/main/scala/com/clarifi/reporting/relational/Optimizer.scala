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

  import PureSelect._

  def optimize(mem: Mem[Nothing, Nothing]): Mem[Nothing, Nothing] = {
    return mem
    TrivialAugment.detrivialize(optimizeMem[Nothing, Nothing](mem, x => x, x => x)._3)
  }

  def optimize(rel: Relation[Nothing, Nothing]): Relation[Nothing, Nothing] = {
    return rel
    val (ns, h, jh, optr) = optimizeRel[Nothing, Nothing](rel, x => x, x => x)
    Annotated(ns, impurify(optr, jh))
  }

  def optimize(ext: Ext[Nothing, Nothing]): Ext[Nothing, Nothing] = {
    return ext
    optimizeExt[Nothing, Nothing](ext, x => x, x => x)._2
  }

  def optimizeExt[M: Equal, R: Equal](ext: Ext[M, R],
                                      hr: R => Header,
                                      hm: M => Header): (Header, Ext[M, R]) = ext match {
    case ExtMem(e) =>
      val (h, _, optm) = optimizeMem(e, hr, hm)
      (h, ExtMem(TrivialAugment.detrivialize(optm)))
    case ExtRel(r, ns) =>
      val (notes, h, jh, r2) = optimizeRel(r, hr, hm)
      (h, ExtRel(Annotated(notes, impurify(r2, jh)), ns))
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
          case (ns, h, _, optr) =>
            val (eh, _, optexpr) = optimizeMem[R, Option[M]](Mem.fromScope(expr), hr, {
                                     case None => h
                                     case Some(ep) => hm(ep)
                                   })
            (eh, eh, TrivialAugment(LetM(ExtRel(Annotated(ns, optr), db), Mem.toScope(detrivialize(optexpr)))))
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
          case (ns, h, jh, e) => (h, h, TrivialAugment(EmbedMem(ExtRel(Annotated(ns, impurify(e, jh)), db))))
        }
        case ExtSM(sm) => (sm.header, sm.header, TrivialAugment(EmbedMem(ext)))
      }
      case QuoteMem(token) => sys.error("Panic: the optimizer found a QuoteMem: " + token)
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

  def coalesceLiteral[M, R](hl: Header,
                            h: Header,
                            jh: Header,
                            ts: NonEmptyList[Record],
                            sel: SelectR[M, R]): Option[(Header, Header, SelectR[M, R])] = {
    val SelectR(rs, cs, where) = sel
    val jk = h.keySet & hl.keySet
    // val functional = {
    //   val tks = ts map (_ filterKeys jk)
    //   tks.length == tks.toSet.length
    // }
    val functional = ts.size <= 1
    val hr = h ++ hl
    if (functional) {
      val ps = literalAsPredicate(ts.map(_ filterKeys jk))
      val cases = literalAsCases(jk, ts)
      Some((hr,
            jh,
            SelectR(rs, cs ++ flattenProjection(cases, cs),
                    Predicate.And(where, ps.postReplaceOp[Id](cvAttr(cs))))))
    } else {
      None
    }
  }

  def coalesceLiterals[M, R](lits: List[(Header, NonEmptyList[Record])],
                             hhs: (Header, Header, SelectR[M, R])):
      (List[(Header, NonEmptyList[Record])], (Header, Header, SelectR[M, R])) = {
    val (work, newLits, newhhs) = lits.foldRight((false, List[(Header, NonEmptyList[Record])](), hhs)) {
      case (p@(hl, ts), (b, l, (hr, jhr, sel))) =>
        coalesceLiteral(hl, hr, jhr, ts, sel) match {
          case Some(osel) => (true, l, osel)
          case None       => (b, p :: l, (hr, jhr, sel))
        }
    }
    if(work) coalesceLiterals(newLits, newhhs) else (newLits, newhhs)
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

  def optimizeAggregates[M, R](rs: List[(List[String], Header, Header, SelectR[M, R])])
      : (List[String], List[(Header, Header, SelectR[M, R])]) = {
    type HH[X] = (Header, Header, X)
    val base = (List[String](), List[(Header, AggregateByGroup[M,R])](), List[HH[SelectR[M,R]]]())
    val (nss, aggs, other) = rs.foldRight(base) {
      case ((ns, h, jh, r), (nss, ag, ot)) => PureSelect.unapply(r, jh) match {
        case Some(a : AggregateByGroup[M, R]) => (ns ++ nss, (h, a) :: ag, ot)
        case _                          => (ns ++ nss, ag, (h, jh, r) :: ot)
      }
    }
    val agmap = aggs.groupBy(ag => (ag._2.rel, ag._2.cs))

    (nss,
    agmap.values.map {
      case Nil => sys.error("optimizeAggregates: Impossible: empty group")
      case List((h, r)) => (h, h, PureSelect(r, h))
      case base :: ags =>
        val (nh, r) = ags.foldRight(base) {
          case ((hl, result), (hr, e)) => (hl ++ hr, result.copy(aggs = result.aggs ++ e.aggs))
        }
        (nh, nh, PureSelect(r, nh))
    }.toList ++ other)
  }

  def optimizeJoin[M, R](rs0: List[(List[String], Header, Header, SelectR[M, R])]):
        (List[String], Header, Header, SelectR[M, R]) = {
    type HH[X] = (Header, Header, X)
    val (notes, rs) = optimizeAggregates(rs0)
    val base = (List[HH[NonEmptyList[Record]]](), List[HH[SelectR[M, R]]]())
    val (lits, cx) = rs.foldRight(base) {
      case (p@(h, jh, r), (l, c)) => PureSelect.unapply(r, jh) match {
        case Some(SmallLit(ts)) => ((h, jh, ts) :: l, c)
        case _                  => (l, p :: c)
      }
    }
    val (h, jh, s) = cx match {
      case s :: ss =>
        val oss = ss.foldRight(s) {
          case ((hl, jhl, sl), (hr, jhr, sr)) => joinSelect(hl, jhl, sl, hr, jhr, sr)
        }
        val (un, css) = coalesceLiterals(lits map { case (x, _, y) => (x, y) }, oss)
        un match {
          case Nil => css
          case (x,y) :: tss =>
            val (h, jh, sel) = css
            val (hun, biglit) = tss.foldRight((x,y.list)) {
              case ((hl, tsl), (hr, tsr)) => (hl ++ hr, joinLiterals(hl.keySet & hr.keySet, tsl.list, tsr))
            }
            def hd = h ++ hun
            def mpt = (hd, hd, PureSelect(RelEmpty(hd), hd))
            biglit.toNel.map(nel => joinSelect(hun, hun, PureSelect(SmallLit(nel), hun), h, jh, sel)).getOrElse(mpt)
        }
      case Nil => lits match {
        case (h, _, ts) :: ls =>
          val (rh, rts) = ls.foldRight(h -> ts.list) {
            case ((hl, _, tsl), (hr, tsr)) => (hl ++ hr, joinLiterals(hl.keySet & hr.keySet, tsl.list, tsr))
          }
          rts.toNel.map(nel => (rh, rh, PureSelect(SmallLit(nel), rh))).getOrElse((rh, rh, PureSelect(RelEmpty(rh), rh)))
        case _ => sys.error("Panic: The impossible happened: optimizing empty joins")
      }
    }
    (notes, h, jh, s)
  }

  def joinSelect[M, R](hl: Header, jhl: Header, sl: SelectR[M, R],
                       hr: Header, jhr: Header, sr: SelectR[M, R]): (Header, Header, SelectR[M, R]) = {
    val SelectR(rsl, prjl, filtl) = sl
    val SelectR(rsr, prjr, filtr) = sr
    val h = hl ++ hr
    if (joinable(jhl.keySet & jhr.keySet, prjl, prjr))
      (h, jhl ++ jhr, SelectR(rsl ++ rsr,
                              prjl ++ prjr,
                              Predicates.all(Seq(filtl, filtr))))
    else (h, h, SelectR(List(impurify(sl, jhl), impurify(sr, jhr)),
                           Header.proj(h),
                           Predicate.Atom(true)))
  }

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

  def whenAggregate[M, R, Z](jh: Header, sel: SelectR[M, R])(f : AggregateByGroup[M, R] => Z)(el: Z): Z =
    PureSelect.unapply(sel, jh) match {
      case Some(agg : AggregateByGroup[M,R]) => f(agg)
      case _ => el
    }

  // first turn every tableproc into a let of a tableproc
  // second lift every let out as far as it can go
  // third join all duplicate lets
  def optimizeRel[M: Equal, R: Equal](rel: Relation[M, R],
                                      hr: R => Header,
                                      hm: M => Header): (List[String], Header, Header, SelectR[M, R]) = rel match {
    case Join(l, r) => optimizeJoin((collectJoin(l) ++ collectJoin(r)).map(optimizeRel(_, hr, hm)))
    // See `joinable` for conditions under which
    // we can combine two selects into one by an
    // associative natural join.
    case JoinOn(r1, r2, cols, mode) =>
      val (nl, orh1, jh1, rl) = optimizeRel(r1, hr, hm)
      val (nr, orh2, jh2, rr) = optimizeRel(r2, hr, hm)
      val h = orh1 ++ orh2
      (nl ++ nr, h, h, PureSelect(JoinOn(impurify(rl, jh1), impurify(rr, jh2), cols, mode), h))
    // Unions can be reinterpreted as a single select if they differ only in filter.
    case Union(r1, r2) =>
      val (nl, h, jh1, rl) = optimizeRel(r1, hr, hm)
      val (nr, _, jh2, rr) = optimizeRel(r2, hr, hm)
      (nl ++ nr, h, h, combineFilters(rl, rr){ (l, r) =>
        Predicates.simplify(Predicate.Or(l, r))
      } getOrElse PureSelect(Union(impurify(rl, jh1), impurify(rr, jh2)), h))
    case Minus(r1, r2) =>
      val (nl, h, jh1, rl) = optimizeRel(r1, hr, hm)
      val (nr, _, jh2, rr) = optimizeRel(r2, hr, hm)
      (nl ++ nr, h, h, combineFilters(rl, rr){ (l, r) =>
        Predicates.simplify(Predicate.And(l, Predicate.Not(r)))
      } getOrElse PureSelect(Minus(impurify(rl, jh1), impurify(rr, jh2)), h))
    case Filter(r, p) =>
      val (ns, h, jh, SelectR(rs, prj, filt)) = optimizeRel(r, hr, hm)
      (ns, h, jh, SelectR(rs, prj, Predicates.simplify(Predicate.And(filt, p.postReplaceOp[Id](cvAttr(prj))))))
    case Project(r, cs) =>
      val (ns, h, jh, sel@SelectR(rs, prj, filt)) = optimizeRel(r, hr, hm)
      val nh = cs.map(_._1.tuple)
      simpleProject(cs) match {
        case Some(scs) => 
          whenAggregate(jh, sel) { agg =>
            (ns, nh, nh, PureSelect(projectAggregate(agg, scs), nh))
          } { (ns, nh, jh, SelectR(rs, flattenProjection(cs, prj), filt)) }
        case None => (ns, nh, jh, SelectR(rs, flattenProjection(cs, prj), filt))
      }
    case Except(r, cs) =>
      val (ns, h, jh, sel@SelectR(rs, prj, filt)) = optimizeRel(r, hr, hm)
      val nh = h -- cs
      whenAggregate(jh, sel) { agg =>
        (ns, nh, nh, PureSelect(exceptAggregate(agg, cs), nh))
      } { (ns, h -- cs, jh, SelectR(rs, prj -- (cs.map(c => Attribute(c, h(c)))), filt)) }
    case Combine(r, attr, op) =>
      val (ns, h, jh, SelectR(rs, prj, filt)) = optimizeRel(r, hr, hm)
      val nh = h + attr.tuple
      (ns, nh, jh, SelectR(rs, prj + (attr -> op.postReplace[Id](cvAttr(prj))), filt))
    case RenameR(r, Attribute(from, ft), to) =>
      val (ns, h, jh, sel) = optimizeRel(r, hr, hm)
      val nh = h mapKeys {
        case col if col == from => to
        case col => col
      }
      whenAggregate(jh, sel){ agg =>
        (ns, nh, nh, PureSelect(renameAggregate(from, to, agg), nh))
      }{ (ns, nh, jh, sel copy (
                    cs = sel.cs mapKeys {
                      case Attribute(nm, t) if nm == from => Attribute(to, t)
                      case attr => attr
                    }))
      }
    case Limit(r, start, end, ord) =>
      val (ns, h, jh, or) = optimizeRel(r, hr, hm)
      (start, end) match {
        case (None, None) => (ns, h, jh, or) // We're not actually limiting anything, so we can just pass things up.
        case _ => (ns, h, h, PureSelect(Limit(impurify(or, jh), start, end, ord), h))
      }
    case AggregateByGroup(r, cs, aggs, grp) =>
      val (ns, _, jh, or) = optimizeRel(r, hr, hm)
      val h = (aggs.map(_._1.tuple).toMap ++ cs.keySet.map(_.tuple))
      (ns, h,h, PureSelect(AggregateByGroup( impurify(or, jh), cs, aggs, grp ), h))
    case Aggregate(r, attr, aggfunc) =>
      val (ns, _, jh, or) = optimizeRel(r, hr, hm)
      val h = Map(attr.tuple)
      (ns, h, h, PureSelect(Aggregate(impurify(or, jh), attr, aggfunc), h))
    case s@SelectR(rs, _, _) =>
      (List(), headerOf(s, hr, hm), rs.map(headerOf(_, hr, hm)).foldLeft(Map():Header)(_ ++ _), s)
    case LetR(ExtMem( l@Literal(t,ts)), e) if ts.length <= smallLitSize =>
      optimizeRel[M,R](Relation.instantiate(SmallLit( l.nel ), e), hr, hm)
    case LetR(r, e) =>
      val (h, r2) = optimizeExt(r, hr, hm)
      val (ns, h2, jh, e2) = optimizeRel[M,Option[R]](Relation.fromScope(e), (r: Option[R]) => r match {
        case None => h
        case Some(x) => hr(x)
      }, hm)
      (ns, h2, h2, PureSelect(LetR(r2, Relation.toScope(impurify(e2,jh))), h2))
    case MemoR(r, pk) =>
      val (ns, h, jh, r2) = optimizeRel(r, hr, hm)
      (ns, h, h, PureSelect(MemoR(impurify(r2, jh), pk), h))
    case TableProc(args, oh, fun, ns) =>
      val h = oh.toMap
      val oargs = TableProc.relFunctor(args)(ir => optimizeRel(ir, hr, hm)._4)
      (List(), h, h, PureSelect(TableProc(oargs, oh, fun, ns), h))
    case Note(tags, under) =>
      val (ns, h, jh, r) = optimizeRel(under, hr, hm)
      (tags ++ ns, h, jh, r)
    case r =>
      implicit def iderr(x: String, xs: String*) = sys.error((x::xs.toList).mkString("\n"))
      val h = Typer.relTyperAux[Id, M, R](r, hr, hm)
      (List(), h, h, PureSelect(r, h))
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

  /** If `left` and `right` are the same except in filter, answer a
    * combination that joins the filters with `bin`, otherwise
    * None.
    */
  private def combineFilters[M: Equal, R: Equal](left: => SelectR[M, R], right: => SelectR[M, R])(
                                                 bin: (=> Predicate, => Predicate) => Predicate) =
    (left, right) match {
      case (SelectR(rs1, prj1, filt1), SelectR(rs2, prj2, filt2))
      if prj1 == prj2 && rs1 == rs2 =>
        Some(SelectR(rs1, prj1, bin(filt1, filt2)))
      case _ => None
    }
}

object PureSelect {
  def apply[M, R](r: Relation[M, R], h: Header): SelectR[M, R] =
    SelectR(List(r), Header.proj(h), Predicate.Atom(true))

  def unapply[M, R](rel: Relation[M, R], h: Header) =
    rel match {
      case SelectR(List(innerRel), proj, Predicate.Atom(true))
      if Header.proj(h) == proj => Some(innerRel)
      case _ => None
    }

  /** Strip all selects that don't do anything from `rel`. */
  def impurify[M, R](rel: Relation[M, R], h: Header) = {
    def recur(rel: Relation[M, R]): Relation[M, R] =
      unapply(rel, h) cata (recur, rel)
    recur(rel)
  }
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
