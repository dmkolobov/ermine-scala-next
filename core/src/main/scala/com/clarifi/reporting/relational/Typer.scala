package com.clarifi.reporting
package relational

import PrimT._

import scalaz.{Monad, NonEmptyList, Show, Validation}
import scalaz.std.either._
// import scalaz.std.list._
import scalaz.syntax.monad._
// import scalaz.syntax.traverse.{ToFunctorOps => _, ToFunctorOpsUnapply => _, _}
import scalaz.syntax.validation._

case class Closed[F[_, _]](out: F[Nothing, Nothing], header: Header) {
    def map[G[_, _]](f: F[Nothing, Nothing] => G[Nothing, Nothing]): Closed[G] =
      Closed[G](f(out), header)
}


object Typer {
  /** R2 (SQL audit O-7/S-02): the tag a binder (`letR`, `letRWithPK`, `letM`, `groupBy`,
    * `accumulate`) puts on its `QuoteR`/`QuoteMem` when it knows the bound relation's
    * header, so a header-inspecting helper (`projectEach`, `rheader`, `leftJoinOr`,
    * `joinWithDefault`) applied to the bound variable can type instead of panicking
    * "Asked for the header of a quote".  Quotes are matched by reference (`eq`), so the
    * tag is a fresh object like the plain `new Object` it replaces. */
  final class Quoted(val header: Header) {
    override def toString = "quote:" + header.toList.sortBy(_._1).mkString("{", ",", "}")
  }

  /** R4 (SQL audit O-11/S-27/L-18/S-10, decision D4): the header of a join by mode.
    * Columns that come only from the side an outer join NULL-fills are nullable; a
    * column present on both sides keeps the type the join key has (an inner match on
    * Left/Right, a coalesce on Full).  The scanner's `joinOn` header should agree with
    * this, or the wire decoder still throws "Unexpected NULL" on an unmatched row. */
  def joinHeader(left: Header, right: Header, mode: JoinMode): Header = {
    val shared = left.keySet intersect right.keySet
    def widen(h: Header, on: Boolean): Header =
      if (!on) h else h map { case (c, t) => if (shared(c)) (c, t) else (c, t.withNull) }
    val l = widen(left, mode == JoinMode.Right || mode == JoinMode.Full)
    val r = widen(right, mode == JoinMode.Left || mode == JoinMode.Full)
    // R4b: a shared column's two types may differ in the nullable flag only (an `unsafe*`
    // outer join's result joined back to a plain relation); the value the join delivers
    // is the left side's on Left, the right side's on Right, on Inner a match (never NULL
    // unless both sides admit it), and on Full a coalesce -- where a NULL key never
    // matches and survives as an unmatched row whose coalesced key is NULL, so the key is
    // nullable if EITHER side's is (review-rel R4b-Full, measured on SQLite).
    val sharedTyped = shared.toList.map { c =>
      val (lt, rt) = (left(c), right(c))
      val nullable = mode match {
        case JoinMode.Left  => lt.nullable
        case JoinMode.Right => rt.nullable
        case JoinMode.Full  => lt.nullable || rt.nullable
        case JoinMode.Inner => lt.nullable && rt.nullable
      }
      c -> (if (nullable) lt.withNull else lt.withoutNull)
    }
    l ++ r ++ sharedTyped
  }

  /** R4b: the header of a union/difference: the columns must agree up to the nullable
    * flag, and a column is nullable iff it is on either side. */
  def unionHeader(top: Header, bottom: Header): Option[Header] =
    if (top.keySet != bottom.keySet) None
    else {
      val bad = top.keys.filter(c => top(c).withoutNull != bottom(c).withoutNull)
      if (bad.nonEmpty) None
      else Some(top map { case (c, t) => c -> (if (t.nullable || bottom(c).nullable) t.withNull else t) })
    }

  /** The error-reporting capability the typer is parameterised over.
    *
    * This was `Errs[F]`, but Scala 3 does not allow a
    * repeated parameter in a function type; a trait keeps every call site
    * (`err(msg)`, `err(head, tail: _*)`) exactly as it was.
    */
  trait Errs[F[+_]] {
    def apply(msg: String, msgs: String*): F[Nothing]
  }

  private def badColumns[F[+_]](cols: List[String])(implicit err: Errs[F]): F[Nothing] = {
    val errs = cols.map("Operation refers to nonexistent column (%s) in header." format _)
    err(errs.head, errs.tail:_*)
  }

  // verifies that `base` subsumes `cols` before returning `z`
  private def columnCheck[F[+_], Z](
    base: Header,
    cols: Set[ColumnName],
    z: Z
  )(implicit F: Monad[F], err: Errs[F]): F[Z] = {
    val freeRefs = cols -- base.keys
    if(freeRefs.isEmpty) z.pure[F] else badColumns(freeRefs.toList)
  }

  private def renameType[F[+_]](
    base: Header,
    attr: Attribute,
    newCol: ColumnName,
    promote: Boolean
  )(implicit F: Monad[F], err: Errs[F]): F[Header] = {
    def prm(ty: PrimT) = if(promote) ty.withNull else ty
    base.lift(attr.name) match {
      case Some(t) if t == attr.t => (base -attr.name + (newCol -> prm(t))).pure[F]
      case Some(_)                => err("Inconsistent type for attribute renaming.")
      case None                   => err("Renaming non-existent attribute")
    }
  }

  private def exceptType[F[+_]](
    base: Header,
    cols: Set[ColumnName]
  )(implicit F: Monad[F], err: Errs[F]): F[Header] =
    columnCheck[F, Header](base, cols, base -- cols)

  private def filterType[F[+_]](
    base: Header,
    pred: Predicate
  )(implicit F: Monad[F], err: Errs[F]): F[Header] =
    columnCheck[F, Header](base, pred.columnReferences, base)

  private def combineType[F[+_]](
    base: Header,
    attr: Attribute,
    op: Op
  )(implicit F: Monad[F], err: Errs[F]): F[Header] =
    columnCheck[F, Header](base, op.columnReferences, base + attr.tuple)

  private def projectType[F[+_]](
    base: Header,
    cols: Map[Attribute, Op]
  )(implicit F: Monad[F], err: Errs[F]): F[Header] =
    columnCheck[F, Header](base, cols flatMap { case (attr, op) => op.columnReferences } toSet, cols.map(_._1.tuple))

  private def aggregateType[F[+_]](
    base: Header,
    attr: Attribute,
    agg: AggFunc
  )(implicit F: Monad[F], err: Errs[F]): F[Header] =
    columnCheck[F, Header](base, agg.columnReferences, Map(attr.tuple))

  private def aggregateByGroupType[F[+_]](
    base: Header,
    cols: Map[Attribute, Op],
    aggs: List[(Attribute,AggFunc)],
    grp: List[Op.ColumnValue]
  )(implicit F: Monad[F], err: Errs[F]): F[Header] =
    columnCheck[F, Header](
      base,
      aggs.flatMap(_._2.columnReferences).toSet ++ cols.keySet.map(_.name) ++ grp.flatMap(_.columnReferences).toSet,
      cols.keys.map(_.tuple).toMap ++ aggs.map(_._1.tuple).toMap)

  private def joinType[F[+_]](
    left: Header,
    right: Header,
    extras: Set[(ColumnName, ColumnName)] = Set(),
    mode: JoinMode = JoinMode.Inner
  )(implicit F: Monad[F], err: Errs[F]): F[Header] = {
    val joinKey = (left.keySet intersect right.keySet map {x => (x,x)} toSet) ++ extras
    // R4b: the nullable flag is not a type mismatch (`joinHeader` decides it)
    val badCols = joinKey collect {
      case (lname,rname) if left(lname).withoutNull != right(rname).withoutNull => (lname, rname) -> (left(lname), right(rname))
    }
    if(badCols isEmpty) joinHeader(left, right, mode).pure[F]
    else {
      val msgs = badCols.toList.map({
        case ((ln, rn), (l, r)) =>
          "Join of relations with mismatching column types: (%s, %s, %s, %s)" format (ln, l.toString, rn, r.toString)
      })
      err(msgs.head, msgs.tail:_*)
    }
  }

  def accumulateType[F[+_]](pid: Header, nid: Header, expr: Header => F[Header], leaves: Header)
                    (implicit F: Monad[F], err: Errs[F]): F[Header] = {
    val v = leaves -- nid.keySet
    val v2 = expr(v)
    v2.flatMap { v2 =>
      if (v2.keySet.intersect(nid.keySet).isEmpty)
        (nid ++ v2).pure[F]
      else
        err("Subquery result of accumulate must not contain the key: %s %s".format(nid.toString, v2.toString))
    }
  }

  def groupByType[F[+_]](m: Header, key: Header, expr: Header => F[Header])(
                         implicit F: Monad[F], err: Errs[F]): F[Header] = {
    val v = m -- key.keySet
    val v2 = expr(v)
    v2.flatMap { v2 =>
      if (!v2.keySet.intersect(key.keySet).isEmpty)
        err("Subquery result of a groupBy must not contain the key: %s %s".
            format(key.toString, v2.toString))
      else (key ++ v2).pure[F]
    }
  }

  private def unionType[F[+_]](
    top: Header,
    bottom: Header,
    operation: String
  )(implicit F: Monad[F], err: Errs[F]): F[Header] = {
    unionHeader(top, bottom) match {
      case Some(h) => h.pure[F]
      case None =>
        val msg = "Cannot %s columns: expected `" + top.toString + "', found `" + bottom.toString + "'."
        err(msg format operation)
    }
  }

  private def limitType[F[+_]](
    base: Header,
    start: Option[Int],
    end: Option[Int],
    order: List[(String, SortOrder)]
  )(implicit F: Monad[F], err: Errs[F]): F[Header] = {
    val badBounds = for {
      from <- start
      to <- end
      if from > to
    } yield "Limit's lower bound %s is after upper bound %s".format(from, to)

    badBounds match {
      case Some(s) => err(s)
      case None    => columnCheck[F, Header](base, order.map(_._1).toSet, base)
    }
  }

  def pivotType[F[+_]](
    hunder: Header,
    pKey: Set[ColumnName],
    pVals: Set[ColumnName],
    outer: Boolean,
    colMap: Map[ColumnName, (Record, Op, PrimExpr)]
  )(implicit f: Monad[F], err: Errs[F]): F[Header] = {
    // D4: a NULL default (`pivot`'s `Null Double`) makes the pivoted column nullable
    val pivCols = colMap mapValues { case (k,o,d) =>
      val t = o.guessTypeUnsafe
      if (d.isNull) t.withNull else t
    }
    val passCols = hunder -- pKey -- pVals
    val overlap = passCols.keySet intersect pivCols.keySet

    columnCheck[F,Unit](hunder, pKey, ()) >>
    columnCheck[F,Unit](hunder, pVals, ()) >>
      (if (overlap isEmpty) f.pure(passCols ++ pivCols)
       else err("Pivot attempts to overwrite columns: " ++ overlap.toString))
  }

  def memTyperAux[F[+_], R, M](
    m: Mem[R, M],
    rtype: R => F[Header],
    mtype: M => F[Header]
  )(implicit F: Monad[F], err: Errs[F]): F[Header] = {
    def go(m: Mem[R, M]): F[Header] = memTyperAux(m, rtype, mtype)
    m match {
      case VarM(v)                    => mtype(v)
      case LimitM(e, start, end, ord) => go(e) flatMap (limitType[F](_, start, end, ord))
      case FilterM(e, pred)           => go(e) flatMap (filterType[F](_, pred))
      case CombineM(e, attr, op)      => go(e) flatMap (combineType[F](_, attr, op))
      case ExceptM(e, cs)             => go(e) flatMap (exceptType[F](_, cs))
      case ProjectM(e, cs)            => go(e) flatMap (projectType[F](_, cs))
      case ProcessM(f, mem)           => go(mem) flatMap (f.outputType(_).pure[F])
      case AggregateM(e, attr, op)    => go(e) flatMap (aggregateType[F](_, attr, op))
      case UnionM(m1, m2)             => (go(m1) |@| go(m2))(unionType[F](_, _, "unionM")).join
      case DifferenceM(m1, m2)        => (go(m1) |@| go(m2))(unionType[F](_, _, "differenceM")).join
      case HashInnerJoin(e1, e2)      => (go(e1) |@| go(e2))(joinType[F](_,_)).join
      case HashLeftJoin(inner, outer) => (go(inner) |@| go(outer))(joinType[F](_, _, Set(), JoinMode.Left)).join // D4: `outer` is NULL-filled
      case AccumulateM(pid, nid, expr, leaves, _) =>
                                         go(leaves) flatMap { hvnid => accumulateType(
                                           pid.toHeader,
                                           nid.toHeader,
                                           (hv: Header) => go(Mem.instantiate(EmptyRel(hv), expr)),
                                           hvnid
                                         )}
      case GroupByM(m, k, expr)       => go(m) flatMap (hvk => groupByType(
                                           hvk, k.map(_.tuple).toMap,
                                           (hv: Header) => go(Mem.instantiate(EmptyRel(hv), expr))))
      case MergeOuterJoin(e1, e2)     => (go(e1) |@| go(e2))(joinType[F](_, _, Set(), JoinMode.Full)).join // D4
      case EmbedMem(e)                => extTyperAux(e, rtype, mtype)
      case ProcedureCall(_, h, _, _)  => h.pure[F]
      case AugmentSM(m, cur, hist)    => memTyperAux(m, rtype, mtype) map (augmentType(_, cur, hist))
      case RenameM(m, attr, col, p)   => go(m) flatMap (renameType[F](_, attr, col, p))
      case MemoMem(m)                 => go(m)
      case QuoteMem(q: Quoted)        => q.header.pure[F] // R2: a quote tagged by its binder
      case (h:HardMem)                => h.header.pure[F]
      case LetM(r, expr) =>
        val h = extTyperAux(r, rtype, mtype)
        memTyperAux(expr, rtype, (m:MLevel[R, M]) => m match {
          case MTop => h
          case MPop(e) => go(e)
        })
      case Pivot(under, pKey, pVals, outer, km) =>
        go(under) flatMap { h => pivotType[F](h, pKey, pVals, outer, km) }
    }
  }

  private def extTyperAux[F[+_], M, R](
    e: Ext[M, R],
    rtype: R => F[Header],
    mtype: M => F[Header]
  )(implicit F: Monad[F], err: Errs[F]): F[Header] =
    e match {
      case ExtSM(sm) => sm.header.pure[F]
      case ExtMem(mem) => memTyperAux(mem, rtype, mtype)
      case ExtRel(rel, _) => relTyperAux(rel, rtype, mtype)
    }

  def relTyperAux[F[+_], M, R](
    rel: Relation[M, R],
    rtype: R => F[Header],
    mtype: M => F[Header]
  )(implicit F: Monad[F], err: Errs[F]): F[Header] = {
    def go(rel: Relation[M, R]): F[Header] = relTyperAux(rel, rtype, mtype)
    rel match {
      case VarR(v)                 => rtype(v)
      case Limit(r, f, t, os)      => go(r) flatMap (limitType[F](_, f, t, os))
      case JoinOn(fst, snd, k, m)  => (go(fst) |@| go(snd))(joinType[F](_, _, k, m)).join
      case Union(fst, snd)         => (go(fst) |@| go(snd))(unionType[F](_, _, "union")).join
      case Minus(fst, snd)         => (go(fst) |@| go(snd))(unionType[F](_, _, "subtract")).join
      case Filter(r, p)            => go(r) flatMap (filterType[F](_, p))
      case Project(r, cols)        => go(r) flatMap (projectType[F](_, cols))
      case Except(r, cols)         => go(r) flatMap (exceptType[F](_, cols))
      case RenameR(r, from, to)    => go(r) flatMap (renameType[F](_, from, to, false))
      case Combine(r, attr, op)    => go(r) flatMap (combineType[F](_, attr, op))
      case Aggregate(r, attr, op)  => go(r) flatMap (aggregateType[F](_, attr, op))
      case AggregateByGroup(r,cs,aggs,grp) => go(r) flatMap (aggregateByGroupType[F](_, cs, aggs, grp))
      case PivotR(under, pKey, pVals, outer, km) =>
        go(under) flatMap { h => pivotType[F](h, pKey, pVals, outer, km) }
      case (r: HardRel)            => r.header.pure[F]
      case MemoR(r, _) => go(r)
      case LetR(r, _, expr) => for {
        h1 <- extTyperAux(r, rtype, mtype)
        h2 <- relTyperAux(expr, (r: RLevel[M, R]) => r match {
          case RTop => h1.pure[F]
          case RPop(e) => go(e)
        }, mtype)
      } yield h2
      case TableProc(args, h, _, _) =>
        TableProc.relFoldable.traverse_(args)(go(_)) >| h.toMap
      case Note(_, under) => go(under)
    }
  }

  def augmentType(h: Header, cur: List[(String, String)], hist: List[(String, String)]): Header =
    if((cur ++ hist) isEmpty)
      h
    else {
      val ch = h + ("issueId" -> StringT(0, false)) ++
                   cur.map(p => p._1 -> StringT(0, false)) ++
                   hist.map(p => p._1 -> StringT(0, false))
      if(hist isEmpty) ch else ch + ("date" -> DateT(false))
    }

  private def nonexistentColumns(cols: List[String]) = {
    val errs = cols.map("Operation refers to nonexistent column (%s) in header." format _)
    NonEmptyList.nel(errs.head, scalaz.IList.fromList(errs.tail)).failure
  }

  type TT[+A] = Either[NonEmptyList[String], A]

  private implicit val eerr: Errs[TT] = new Errs[TT] {
    def apply(x: String, xs: String*): Either[NonEmptyList[String], Nothing] =
      Left(NonEmptyList.nel(x, scalaz.IList.fromList(xs.toList)))
  }

  def memTyper(mem: Mem[Nothing, Nothing]): TypeTag =
    Validation.fromEither(memTyperAux[TT, Nothing, Nothing](mem, x => x, x => x))

  def relTyper(rel: Relation[Nothing, Nothing]): TypeTag =
    Validation.fromEither(relTyperAux[TT, Nothing, Nothing](rel, x => x, x => x))

  def extTyper(ext: Ext[Nothing, Nothing]): TypeTag =
    Validation.fromEither(extTyperAux[TT, Nothing, Nothing](ext, x => x, x => x))

  def closedMem(mem: Mem[Nothing, Nothing]): Closed[Mem] =
    memTyper(mem).fold(e => sys.error(e.toString), x => Closed(mem, x))

  def closedRel(rel: Relation[Nothing, Nothing]): Closed[Relation] =
    relTyper(rel).fold(e => sys.error(e.toString), x => Closed(rel, x))

  def closedExt(ext: Ext[Nothing, Nothing]): Closed[Ext] =
    extTyper(ext).fold(e => sys.error(e.toString), x => Closed(ext, x))

}

