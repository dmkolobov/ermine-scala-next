package com.clarifi.reporting
package remote

import f0.{Source => _, _}
import f0.Effects._
import f0.Formats._
import f0.Writers._
import f0.Readers._
import com.clarifi.reporting._
import PrimT._
import SortOrder._
import Op._
import AggFunc._
import Predicate._
import java.util.UUID
import relational.ProcessSymbols.{Median, WeightedMean, WeightedHarmonicMean}

import com.clarifi.reporting.relational._

import scalaz.\/
import scalaz.Scalaz._

object Format {
  def recordW: Writer[Record, RepeatF[StringF & PrimExprF]] =
    repeatW(tuple2W(stringW, primExprW)) cmap ((t: Record) => t.toList)

  def recordR: Reader[Record, RepeatF[StringF & PrimExprF]] =
    listR(tuple2R(stringR label "column-name", primExprR label "column-value")
    ) map ((t: List[(String, PrimExpr)]) => t.toMap) label "row"

  val colorW: Writer[java.awt.Color, IntF] =
    intW.cmap(_.getRGB) // preserves alpha, should be called getRGBA
  val colorR: Reader[java.awt.Color, IntF] =
    intR.map(new java.awt.Color(_, true))

  /**
   * Using the old (incorrect) F0 style of writing streams, where
   * 1 meant termination (Nil), and 0 meant continue (Cons)
   * This has been changed in F0 so that it is consistent with Haskell stream serialization
   */
  lazy val rowsW = {
    def streamW[A,F1](w: Writer[A,F1]): Writer[TraversableOnce[A],StreamF[F1]] = new Writer[TraversableOnce[A],StreamF[F1]] {
      def bind(o: Sink) = {
        val bindA = w.bind(o)
        (as) => {
          as.foreach(a => { o(0); bindA(a) })
          o(1)
          effectW[StreamF[F1]]
        }
      }
    }
    streamW(recordW).orError.selfDescribing
  }


  /**
   * Using the old (incorrect) F0 style of readings streams, where
   * 1 meant termination (Nil), and 0 meant continue (Cons)
   * This has been changed in F0 so that it is consistent with Haskell stream serialization
   */
  lazy val rowsR = {
    def streamR[A,F](r: Reader[A,F]): Reader[List[A],StreamF[F]] =
      foldStreamR(r)(List[A]())((buf,a) => a :: buf) map (_.reverse)

    def foldStreamR[A,B,F](r: Reader[A,F])(z: B)(f: (B,A) => B): Reader[B,StreamF[F]] = new Reader[B,StreamF[F]] {
      def bind(s: f0.Source): Get[B] = new Get[B] {
        val elem = lazyStreamR(r).bind(s)
        def get = {
          var acc = z
          var cur = elem.get
          while (cur != None) { acc = f(acc, cur.get); cur = elem.get }
          acc
        }
      }
    }
    def lazyStreamR[A,F](r: Reader[A,F]): Reader[Option[A],StreamF[F]] = new Reader[Option[A],StreamF[F]] {
      def bind(s: f0.Source): Get[Option[A]] = new Get[Option[A]] {
        val elem = r.bind(s)
        var eof = false
        def get = {
          eof = s.readByte == 1
          if (eof) { eof = false; None }
          else Some(elem.get)
        }
      }
    }
    eitherR(stringR, streamR(recordR)).label("rows").selfDescribing
  }
  unify(rowsW, rowsR)

  def unify[A,B,F](w: Writer[A,F], r: Reader[B,F]): Unit = ()

  def mapW[K, F1, V, F2](k: Writer[K, F1], v: Writer[V, F2]) =
    repeatW(tuple2W(k, v))

  def mapR[K, F1, V, F2](k: Reader[K, F1], v: Reader[V, F2]) =
    listR(p2R(k, v)(_ -> _)).map(_.toMap)

  private def R_\/[L, F1, R, F2](l: Reader[L, F1], r: Reader[R, F2]
                                ): Reader[L \/ R, S2[F1, F2]] =
    s2R(l, r)(\/.left, \/.right)

  private def W_\/[L, F1, R, F2](l: Writer[L, F1], r: Writer[R, F2]
                                ): Writer[L \/ R, S2[F1, F2]] =
    s2W(l, r)((l, r) => (_ fold (l, r)))

  def extW[M,R](implicit wm: Writer[M, DynamicF],
                         wr: Writer[R, DynamicF]): Writer[Ext[M, R], DynamicF] =
    s3W(tuple2W(relW(wm, wr), stringW), memW(wm, wr), smW)((r, m, s) => (ext: Ext[M, R]) => ext match {
      case ExtRel(rel, db) => r((rel, db))
      case ExtMem(mem) => m(mem)
      case ExtSM(sm) => s(sm)
    }).erase

  def extR[M,R](implicit rm: Reader[M, DynamicF],
                         rr: Reader[R, DynamicF]): Reader[Ext[M, R], DynamicF] =
    union3R(p2R(relR[M, R], stringR)(ExtRel(_, _)),
            memR[R,M].map(ExtMem(_)),
            smR.map(ExtSM(_))).erase

  def smW: Writer[SM, DynamicF] =
    s2W(tuple2W(stringW,stringW), tuple2W(stringW,stringW))((look, hist) => (sm: SM) => sm match {
      case LookupSM(fld, attr) => look(fld, attr)
      case HistoricalSM(fld, attr) => hist(fld, attr)
    }).erase

  def smR: Reader[SM, DynamicF] = union2R(p2R(stringR,stringR)(LookupSM(_,_)),
                                          p2R(stringR,stringR)(HistoricalSM(_,_))).erase

  def memR[R,M](implicit rm: Reader[M, DynamicF],
                         rr: Reader[R, DynamicF]): Reader[Mem[R, M], DynamicF] =
    fixR((self: Reader[Mem[R, M], DynamicF]) => union19R(
      rm.map(VarM(_)),
      p2R(extR[M,R], memR[R, MLevel[R, M]](mLevelR, rr))(LetM(_, _)),
      p2R(self, predicateR)(FilterM(_, _)),
      p2R(self, mapR(attributeR, opR))(ProjectM(_, _)),
      p2R(self, listR(stringR))((a, b) => ExceptM(a, b.toSet)),
      p3R(self, attributeR, opR)(CombineM(_, _, _)),
      p3R(self, attributeR, aggR)(AggregateM(_, _, _)),
      p2R(self, self)(HashInnerJoin(_, _)),
      p2R(self, self)(MergeOuterJoin(_, _)),
      extR[M,R].map(EmbedMem(_)),
      p4R(listR(primExprR), headerR, stringR, listR(stringR))(ProcedureCall(_, _, _, _)),
      listR(recordR).map((xs: List[Record]) => Literal(xs.toNel.get)),
      headerR.map(EmptyRel(_)),
      p3R(self, listR(attributeR), memR[R, MLevel[R, M]](mLevelR, rr))(GroupByM.apply),
      p4R(self, attributeR, stringR, booleanR)(RenameM.apply),
      p2R(self, self)(HashLeftJoin.apply),
      p5R(attributeR, attributeR, memR[R, MLevel[R,M]](mLevelR, rr), self, self)(AccumulateM.apply),
      p2R(processSymbolR, self)(ProcessM.apply),
      p5R(self, listR(stringR), listR(stringR), booleanR, mapR(recordR, tuple3R(stringR, opR, primExprR)))(
        (a,b,c,d,e) => Pivot(a,b.toSet,c.toSet,d,e))
    ).erase)

  def memW[R,M](implicit wm: Writer[M, DynamicF],
                         wr: Writer[R, DynamicF]): Writer[Mem[R, M], DynamicF] =
    fixW((self: Writer[Mem[R, M], DynamicF]) => s19W(
      // VarM
      wm
      // LetM
      , tuple2W(extW[M, R], memW[R,MLevel[R, M]](mLevelW, wr)) erase : Writer[(Ext[M,R],Mem[R,MLevel[R,M]]), DynamicF]
      // FilterM
      , tuple2W(self, predicateW) erase : Writer[(Mem[R,M], Predicate), DynamicF]
      // ProjectM
      , tuple2W(self, mapW(attributeW, opW)) erase : Writer[(Mem[R,M],Map[Attribute,Op]),DynamicF]
      // ExceptM
      , tuple2W(self, repeatW(stringW)) erase : Writer[(Mem[R,M],Set[String]),DynamicF]
      // CombineM
      , tuple3W(self, attributeW, opW) erase : Writer[(Mem[R,M],Attribute,Op),DynamicF]
      // AggregateM
      , tuple3W(self, attributeW, aggW) erase : Writer[(Mem[R,M],Attribute,AggFunc),DynamicF]
      // HashInnerJoin
      , tuple2W(self, self) erase : Writer[(Mem[R,M],Mem[R,M]),DynamicF]
      // MergeOuterJoin
      , tuple2W(self, self) erase : Writer[(Mem[R,M],Mem[R,M]),DynamicF]
      // EmbedMem
      , extW[M, R] erase : Writer[Ext[M,R],DynamicF]
      // ProcedureCall
      , tuple4W(repeatW(primExprW), headerW, stringW, repeatW(stringW)) erase
          : Writer[(List[PrimExpr],Header,String,List[String]),DynamicF]
      // Literal
      , repeatW(recordW) erase : Writer[List[Record],DynamicF]
      // EmptyRel
      , headerW erase : Writer[Header,DynamicF]
      // GroupByM
      , tuple3W(self, repeatW(attributeW), memW[R,MLevel[R, M]](mLevelW, wr)) erase
          : Writer[(Mem[R,M],List[Attribute], Mem[R,MLevel[R,M]]),DynamicF]
      // RenameM
      , tuple4W(self, attributeW, stringW, booleanW) erase : Writer[(Mem[R,M],Attribute,String,Boolean),DynamicF]
      // HashLeftJoin
      , tuple2W(self, self) erase : Writer[(Mem[R,M],Mem[R,M]),DynamicF]
      // AccumulateM
      , tuple5W(attributeW, attributeW, memW[R,MLevel[R,M]](mLevelW, wr), self, self) erase
          : Writer[(Attribute, Attribute,Mem[R,MLevel[R,M]],Mem[R,M],Mem[R,M]),DynamicF]
      // ProcessM
      , tuple2W(processSymbolW, self) erase : Writer[(ProcessSymbol, Mem[R,M]),DynamicF]
      // Pivot
      , tuple5W(self, repeatW(stringW), repeatW(stringW), booleanW, mapW(recordW,tuple3W(stringW, opW, primExprW))) erase
          : Writer[(Mem[R,M],Set[String],Set[String],Boolean,Map[Record,(String,Op,PrimExpr)]),DynamicF]
    )((v, let, fil, pro, exc, com, agg, hashIn, mer, emb, proc, lit, emp, grpBy, ren, hashLeft, accum, process, pivot) =>
      (m: Mem[R, M]) => m match {
        case VarM(x) => v(x)
        case LetM(a, b) => let((a, b))
        case FilterM(a, b) => fil((a, b))
        case ProjectM(a, b) => pro((a, b))
        case ExceptM(a, b) => exc((a, b))
        case RenameM(a, b, c, d) => ren((a,b,c,d))
        case CombineM(a, b, c) => com((a, b, c))
        case AggregateM(a, b, c) => agg((a, b, c))
        case HashInnerJoin(a, b) => hashIn((a, b))
        case HashLeftJoin(a, b) => hashLeft((a, b))
        case MergeOuterJoin(a, b) => mer((a, b))
        case EmbedMem(e) => emb(e)
        case ProcedureCall(a, b, c, d) => proc((a, b, c, d))
        case Literal(x, xs) => lit(x :: xs.toList)
        case EmptyRel(h) => emp(h)
        case GroupByM(m, k, e) => grpBy((m, k, e))
        case AccumulateM(a,b,c,d,e) => accum((a,b,c,d,e))
        case ProcessM(a,b) => process((a,b))
        case Pivot(a,b,c,d,e) => pivot((a,b,c,d,e))
        case QuoteMem(_) => sys.error("Can't serialize a QuoteMem! (it has just a raw object in it.)")
      }
    ).erase)

  def processSymbolR: Reader[ProcessSymbol, DynamicF] =
    union3R(
      attributeR.map(Median),
      p2R(attributeR, attributeR)(WeightedMean),
      p2R(attributeR, attributeR)(WeightedHarmonicMean)
    ) erase

  def processSymbolW: Writer[ProcessSymbol, DynamicF] =
    s3W(
      attributeW,
      tuple2W(attributeW, attributeW),
      tuple2W(attributeW, attributeW)
    )((med, wmean, whmean) => (ps: ProcessSymbol) => ps match {
      case Median(v) => med(v)
      case WeightedMean(w, v) => wmean((w,v))
      case WeightedHarmonicMean(w,v) => whmean((w,v))
    }) erase

  def rLevelR[M, R](implicit rm: Reader[M, DynamicF],
                             rr: Reader[R, DynamicF]): Reader[RLevel[M, R], DynamicF] =
    optionR(relR[M,R]) map {
      case None => RTop
      case Some(x) => RPop(x)
    } erase

  def rLevelW[M, R](implicit wm: Writer[M, DynamicF],
                             wr: Writer[R, DynamicF]): Writer[RLevel[M, R], DynamicF] =
    optionW(relW[M,R]) cmap ((x: RLevel[M, R]) => x match {
      case RTop => None
      case RPop(x) => Some(x)
    }) erase

  def mLevelR[R, M](implicit rr: Reader[R, DynamicF],
                             rm: Reader[M, DynamicF]): Reader[MLevel[R, M], DynamicF] =
    optionR(memR[R,M]) map {
      case None => MTop
      case Some(x) => MPop(x)
    } erase

  def mLevelW[R, M](implicit wr: Writer[R, DynamicF],
                             wm: Writer[M, DynamicF]): Writer[MLevel[R, M], DynamicF] =
    optionW(memW[R,M]) cmap ((x: MLevel[R, M]) => x match {
      case MTop => None
      case MPop(x) => Some(x)
    }) erase

  def relW[M,R](implicit wm: Writer[M, DynamicF],
                         wr: Writer[R, DynamicF]): Writer[Relation[M, R], DynamicF] =
    fixW((self: Writer[Relation[M, R], DynamicF]) =>
      s18W(wr, // Var
           tuple4W(self, optionW(intW), optionW(intW), repeatW(tuple2W(stringW, booleanW))), // Limit
           tuple3W(repeatW(self), mapW(attributeW, opW), predicateW), // Select
           tuple2W(extW(wm, wr), relW(wm, rLevelW(wm, wr))), // Let
           tuple2W(self, self), // Join
           tuple3W(self, self, repeatW(tuple2W(stringW, stringW))), // JoinOn
           tuple2W(self, self), // Union
           tuple2W(self, self), // Minus
           tuple2W(self, predicateW), // Filter
           tuple2W(self, mapW(attributeW, opW)), // Project
           tuple2W(self, repeatW(stringW)), // Except
           tuple3W(self, attributeW, opW), // Combine
           tuple3W(self, attributeW, aggW), // Aggregate
           tuple2W(headerW, tuple2W(stringW, repeatW(stringW))), // Table
           tuple4W(repeatW(W_\/(tuple2W(stringW, self), primExprW)), orderedHeaderW, stringW, repeatW(stringW)), // TableProc
           headerW, // RelEmpty
           repeatW(recordW), // SmallLit
           self
         )((v, lim, sel, let, join, on, un, min, fil, proj, exc, comb, agg, tab, tabproc, empt, sl, m) =>
           (r: Relation[M, R]) => r match {
             case VarR(x) => v(x)
             case Limit(a, b, c, d) => lim((a, b, c, d.map(p => (p._1, p._2 == Asc)).toList))
             case SelectR(a, b, c) => sel((a, b, c))
             case LetR(a, b) => let((a, b))
             case Join(a, b) => join((a, b))
             case JoinOn(a, b, c) => on((a, b, c))
             case Union(a, b) => un(a -> b)
             case Minus(a, b) => min(a -> b)
             case Filter(a, b) => fil(a -> b)
             case Project(a, b) => proj((a, b.toList))
             case Except(a, b) => exc((a, b.toList))
             case Combine(a, b, c) => comb((a, b, c))
             case Aggregate(a, b, c) => agg((a, b, c))
             case Table(a, b) => tab((a, (b.name, b.schema)))
             case TableProc(a, b, c, d) => tabproc((a, b, c, d))
             case RelEmpty(h) => empt(h)
             case SmallLit(ts) => sl(ts.toList)
             case MemoR(r) => m(r)
             case QuoteR(_) => sys.error("Can't serialize a QuoteR! (it has just a raw object in it.)")
             // Don't put a catch all here, so we can get compile errors.
           }) erase)

  def relR[M, R](implicit rm: Reader[M, DynamicF], rr: Reader[R, DynamicF]): Reader[Relation[M, R], DynamicF] =
    fixR((self: Reader[Relation[M, R], DynamicF]) => union18R(
      rr.map(VarR(_)),
      p4R(self, optionR(intR), optionR(intR), listR(p2R(stringR, sortOrderR)((_, _))))(Limit(_, _, _, _)),
      p3R(listR(self), mapR(attributeR, opR), predicateR)(SelectR(_, _, _)),
      p2R(extR(rm, rr), relR(rm, rLevelR(rm, rr)))(LetR(_, _)),
      p2R(self, self)(Join(_, _)),
      p3R(self, self, listR(tuple2R(stringR, stringR)) map (_.toSet))(JoinOn(_, _, _)),
      p2R(self, self)((a, b) => Union(a, b)),
      p2R(self, self)((a, b) => Minus(a, b)),
      p2R(self, predicateR)((a, b) => Filter(a, b)),
      p2R(self, mapR(attributeR, opR))(Project(_, _)),
      p2R(self, listR(stringR))((a, b) => Except(a, b.toSet)),
      p3R(self, attributeR, opR)(Combine(_, _, _)),
      p3R(self, attributeR, aggR)(Aggregate(_, _, _)),
      p2R(headerR, p2R(stringR, listR(stringR))(TableName(_, _)))(Table(_, _)),
      p4R(listR(R_\/(p2R(stringR, self)((_,_)), primExprR)),
          orderedHeaderR, stringR, listR(stringR))(TableProc(_, _, _, _)),
      headerR.map(RelEmpty(_)),
      listR(recordR).map(xs => SmallLit(xs.toNel.get)),
      self.map(MemoR(_))
    ) erase)

  lazy val orderedHeaderR: Reader[Header.Ordered, OrderedHeaderF] =
    listR(tuple2R(stringR, primTR))

  lazy val headerR: Reader[Header, HeaderF] = orderedHeaderR map (_.toMap)
  lazy val sourceR: Reader[Source, SourceF] = tuple2R(stringR, listR(stringR)) map {
    case (a, b) => Source(a, b)
  }
  lazy val sourcedR: Reader[Sourced, SourcedF] = tuple2R(listR(sourceR) map (_.toSet), headerR map (_.success))
  lazy val primTR: Reader[PrimT, PrimTF] = union9R(
    booleanR map (IntT(_)),
    booleanR map (ByteT(_)),
    booleanR map (ShortT(_)),
    booleanR map (LongT(_)),
    p2R(intR, booleanR)(StringT.apply),
    booleanR map (DateT(_)),
    booleanR map (DoubleT(_)),
    booleanR map (BooleanT(_)),
    booleanR map (UuidT(_))
  )

  lazy val primExprR: Reader[PrimExpr, PrimExprF] =
    union10R(p2R(booleanR, stringR)(StringExpr(_,_)),
             p2R(booleanR, doubleR)(DoubleExpr(_,_)),
             p2R(booleanR, byteR)(ByteExpr(_,_)),
             p2R(booleanR, shortR)(ShortExpr(_,_)),
             p2R(booleanR, longR)(LongExpr(_,_)),
             p2R(booleanR, intR)(IntExpr(_,_)),
             p2R(booleanR, longR)((b, l) => DateExpr(b, new java.util.Date(l))),
             p2R(booleanR, booleanR)(BooleanExpr(_,_)),
             p2R(booleanR, stringR)((b, s) => UuidExpr(b, UUID.fromString(s))),
             primTR map (NullExpr(_)))

  lazy val predicateR: Reader[Predicate, DynamicF] = fixR[Predicate, DynamicF](self =>
    union8R(booleanR map (x => Predicate.Atom(x)),
            p2R(opR, opR)((a, b) => Lt(a, b)),
            p2R(opR, opR)((a, b) => Gt(a, b)),
            p2R(opR, opR)((a, b) => Eq(a, b)),
            self map (was => Not(was)),
            p2R(self, self)((a, b) => Or(a, b)),
            p2R(self, self)((a, b) => And(a, b)),
            opR map IsNull) erase)

  lazy val attributeR: Reader[Attribute, AttributeF] =
    p2R(stringR, primTR)(Attribute(_, _))

  lazy val opR: Reader[Op, DynamicF] = fixR[Op, DynamicF](self => union14R(
    primExprR map OpLiteral,
    p2R(stringR, primTR)(ColumnValue),
    p2R(self, self)((a, b) => Add(a, b)),
    p2R(self, self)((a, b) => Sub(a, b)),
    p2R(self, self)((a, b) => Mul(a, b)),
    p2R(self, self)((a, b) => FloorDiv(a, b)),
    p2R(self, self)((a, b) => DoubleDiv(a, b)),
    p2R(self, self)((a, b) => Pow(a, b)),
    listR(self) map (x => Concat(x)),
    p3R(predicateR, self, self)(If),
    p2R(self, self)(Coalesce),
    p3R(self, intR, timeUnitR)(DateAdd),
    p3R(timeUnitR, self, self)(DateDiff),
    p5R(stringR, stringR, listR(stringR), listR(self), primTR)(Funcall)) erase)

  lazy val aggR: Reader[AggFunc, DynamicF] = union9R(
    unitR   map (_ => Count),
    opR map (Sum(_)),
    opR map (Avg(_)),
    opR map (Min(_)),
    opR map (Max(_)),
    opR map (Stddev(_)),
    opR map (Variance(_)),
    p2R(opR,opR)(WMean(_,_)),
    p2R(opR,opR)(WHMean(_,_))) erase

  type SortOrderF = BooleanF
  lazy val sortOrderR: Reader[SortOrder, SortOrderF] = booleanR map (x => if (x) Asc else Desc)
  lazy val sortOrderW: Writer[SortOrder, SortOrderF] = booleanW cmap ((_:SortOrder) == SortOrder.Asc)

  lazy val orderByR = listR(tuple2R(stringR, sortOrderR))
  lazy val orderByW = repeatW(tuple2W(stringW, sortOrderW))

  lazy val timeUnitR: Reader[TimeUnit, IntF] = intR map {
    case 0 => TimeUnit.Day
    case 1 => TimeUnit.Week
    case 2 => TimeUnit.Month
    case 3 => TimeUnit.Year
    case 4 => TimeUnit.Millisecond
  }
  lazy val timeUnitW: Writer[TimeUnit, IntF] = intW cmap {
    case TimeUnit.Day => 0
    case TimeUnit.Week => 1
    case TimeUnit.Month => 2
    case TimeUnit.Year => 3
    case TimeUnit.Millisecond => 4
  }

  lazy val opW: Writer[Op, DynamicF] = fixW[Op, DynamicF]{self =>
    lazy val binopW = tuple2W(self, self)
    s14W(primExprW, tuple2W(stringW, primTW), binopW, binopW,
         binopW, binopW, binopW, binopW, repeatW(self),
         tuple3W(predicateW, self, self),
         binopW,
         tuple3W(self, intW, timeUnitW),
         tuple3W(timeUnitW, self, self),
         tuple5W(stringW, stringW, repeatW(stringW), repeatW(self), primTW))(
    (opliteral, columnvalue, add, sub, mul, floor, div, pow, cat, oif, coalesce, dateadd, datediff, funcall) => (r: Op) => r match {
      case OpLiteral(lit) => opliteral(lit)
      case ColumnValue(cn, ty) => columnvalue(cn -> ty)
      case Add(a, b) => add(a -> b)
      case Sub(a, b) => sub(a -> b)
      case Mul(a, b) => mul(a -> b)
      case FloorDiv(a, b) => floor(a -> b)
      case DoubleDiv(a, b) => div(a -> b)
      case Pow(a, b) => pow(a -> b)
      case Concat(ss) => cat(ss.toList)
      case If(test, c, a) => oif((test, c, a))
      case Coalesce(l, r) => coalesce(l, r)
      case DateAdd(d, n, u) => dateadd(d, n, u)
      case DateDiff(u, s, e) => datediff(u, s, e)
      case Funcall(n, db, ns, args, ty) => funcall((n, db, ns, args, ty))
    }) erase}
  lazy val aggW: Writer[AggFunc, DynamicF] = s9W(unitW, opW, opW, opW, opW, opW, opW, tuple2W(opW,opW), tuple2W(opW,opW))(
    (count, sum, avg, min, max, stddev, variance, wmean, whmean) =>
      (r:AggFunc) =>
        r(count(()), sum, avg, min, max, stddev, variance, Function.untupled(wmean), Function.untupled(whmean))) erase
  lazy val orderedHeaderW: Writer[Header.Ordered, OrderedHeaderF] =
    repeatW(tuple2W(stringW, primTW))
  lazy val headerW: Writer[Header, HeaderF] = orderedHeaderW cmap ((h: Header) =>
    h.toList)
  lazy val sourceW: Writer[Source, SourceF] = tuple2W(stringW, repeatW(stringW)) cmap ((s: Source) =>
    (s.source, s.namespace))
  lazy val attributeW: Writer[Attribute, StringF & PrimTF] = p2W(stringW, primTW)(f =>
    (r: Attribute) => f(r.name, r.t))
  lazy val primTW: Writer[PrimT, PrimTF] =
    s9W(booleanW, // Int
        booleanW, // Byte
        booleanW, // Short
        booleanW, // Long
        tuple2W(intW, booleanW), // String
        booleanW, // Date
        booleanW, // Double
        booleanW, // Boolean
        booleanW // UUID
       )((i, b, sh, ln, str, dt, dbl, bool, uuid) => (r: PrimT) => r match {
         case IntT(n) => i(n)
         case ByteT(n) => b(n)
         case ShortT(n) => sh(n)
         case LongT(n) => ln(n)
         case StringT(l, n) => str(l -> n)
         case DateT(n) => dt(n)
         case DoubleT(n) => dbl(n)
         case BooleanT(n) => bool(n)
         case UuidT(n) => uuid(n)
       })
  lazy val predicateW: Writer[Predicate, DynamicF] = fixW[Predicate, DynamicF](self =>
    s8W(booleanW, // Atom
        tuple2W(opW, opW), // Lt
        tuple2W(opW, opW), // Gt
        tuple2W(opW, opW), // Eq
        self, // Not
        tuple2W(self, self), // Or
        tuple2W(self, self), // And
        opW // IsNull
       )((atom, lt, gt, eq, not, or, and, isNull) => (r: Predicate) =>
        r match {
          case Predicate.Atom(x) => atom(x)
          case Lt(x, y) => lt(x -> y)
          case Gt(x, y) => gt(x -> y)
          case Eq(x, y) => eq(x -> y)
          case Not(x) => not(x)
          case Or(x, y) => or(x -> y)
          case And(x, y) => and(x -> y)
          case IsNull(x) => isNull(x)
        }) erase)
  lazy val primExprW: Writer[PrimExpr, PrimExprF] =
    s10W(tuple2W(booleanW, stringW), tuple2W(booleanW, doubleW), tuple2W(booleanW, byteW), tuple2W(booleanW, shortW), tuple2W(booleanW, longW), tuple2W(booleanW, intW), tuple2W(booleanW, longW), tuple2W(booleanW, booleanW), tuple2W(booleanW, stringW), primTW)(
      (str, dbl, byt, sho, lon, i, dt, bool, uuid, nl) => (r: PrimExpr) => r match {
        case StringExpr(nl, s) => str(nl, s)
        case DoubleExpr(nl, d) => dbl(nl, d)
        case ByteExpr(nl, b) => byt(nl, b)
        case ShortExpr(nl, s) => sho(nl, s)
        case LongExpr(nl, l) => lon(nl, l)
        case IntExpr(nl, n) => i(nl, n)
        case DateExpr(nl, d) => dt(nl, d.getTime)
        case BooleanExpr(nl, b) => bool(nl, b)
        case UuidExpr(nl, u) => uuid(nl, u.toString)
        case NullExpr(t) => nl(t)
      })

  type PrimTF = S9[BooleanF       , // Int
                   BooleanF       , // Byte
                   BooleanF       , // Short
                   BooleanF       , // Long
                   IntF & BooleanF, // String
                   BooleanF       , // Date
                   BooleanF       , // Double
                   BooleanF       , // Boolean
                   BooleanF]        // UUID
  type AttributeF = StringF & PrimTF
  type OrderedHeaderF = RepeatF[AttributeF]
  type HeaderF = OrderedHeaderF
  type SourcedF = RepeatF[SourceF] & HeaderF
  type SourceF = P2[StringF, RepeatF[StringF]]
  type PrimExprF = S10[BooleanF & StringF,
                       BooleanF & DoubleF,
                       BooleanF & ByteF,
                       BooleanF & ShortF,
                       BooleanF & LongF,
                       BooleanF & IntF,
                       BooleanF & LongF, // Date
                       BooleanF & BooleanF,
                       BooleanF & StringF, // UUID
                       PrimTF] // Null
  type BinStringF = StringF & StringF
  type BinOpF = FixF[OpF[SelfF]] & FixF[OpF[SelfF]]
  type PredicateF[A] = S7[BooleanF, BinOpF, BinOpF, BinOpF,
                          A, A & A, A & A]
  type OpF[A] = S11[PrimExprF       , // OpLiteral
                    StringF & PrimTF, // ColumnValue
                    A & A           , // Add
                    A & A           , // Sub
                    A & A           , // Mul
                    A & A           , // FloorDiv
                    A & A           , // DoubleDiv
                    A & A           , // Pow
                    RepeatF[A]      , // Concat
                    DynamicF & A & A, // If
                    StringF & StringF & RepeatF[StringF] & RepeatF[A] & PrimTF] // Funcall
  type AggF = S7[UnitF,            // Count
                 FixF[OpF[SelfF]], // Sum
                 FixF[OpF[SelfF]], // Avg
                 FixF[OpF[SelfF]], // Min
                 FixF[OpF[SelfF]], // Max
                 FixF[OpF[SelfF]], // Stddev
                 FixF[OpF[SelfF]]] // Variance

  // these should probably be someplace else...
  import scalaz.NonEmptyList
  type NelF[F] = P2[F, RepeatF[F]]
  def nelR[A, F](r: Reader[A, F]): Reader[NonEmptyList[A], NelF[F]] = tuple2R(r, listR(r)) map {
    case (h, t) => NonEmptyList(h, t:_*)
  }

  def nelW[A, F](w: Writer[A, F]): Writer[NonEmptyList[A], NelF[F]] = p2W(w, repeatW(w))(f =>
    (n:NonEmptyList[A]) => f(n.head, n.tail))

  import writers.{Legend, LegendColumns, Presentation, SortDirection,
                  SortStrategy, Format => WFormat}

  type WFormatF[A] = S10[UnitF, // Default
                     A, // Markdown
                     StringF, // Constant
                     BooleanF :: BooleanF :: IntF :: BooleanF, // Percent
                     BooleanF :: BooleanF :: StringF, // Currency
                     UnitF, // DateRange
                     BooleanF :: BooleanF :: IntF,  // Round
                     BooleanF :: BooleanF :: IntF,  // IntegralRound
                     IntF,  // Truncate
                     A  // Pr1
                   ]

  lazy val wformatR = fixFR[WFormat,WFormatF](self => union10R(
    unitR   map (_ => WFormat.Default),
    self map (inner => WFormat.Markdown(inner) ),
    stringR map (s => WFormat.Constant(s)),
    p4R(booleanR,booleanR,intR, booleanR)(WFormat.Percentage),
    p3R(booleanR,booleanR,stringR)(WFormat.Currency),
    unitR   map (_ => WFormat.DateRange),
    p3R(booleanR,booleanR,intR)(WFormat.Round),
    p3R(booleanR,booleanR,intR)(WFormat.IntegralRound),
    intR    map (i => WFormat.Truncate(i)),
    self map (inner => WFormat.Pr1(inner) )
  ))

  lazy val wformatW = fixFW[WFormat, WFormatF]( self =>
    s10W(unitW, self, stringW, tuple4W(booleanW, booleanW, intW, booleanW), tuple3W(booleanW,booleanW,stringW), unitW, tuple3W(booleanW,booleanW,intW), tuple3W(booleanW,booleanW,intW), intW, self)(
      (d, md, k, p, c, dr, r, sr, t, pr1) => (w: WFormat) => w match {
        case WFormat.Default              => d(())
        case WFormat.Markdown(f)          => md(f)
        case WFormat.Constant(s)          => k(s)
        case WFormat.Percentage(b,b1,r, pad) => p((b,b1,r, pad))
        case WFormat.Currency(b,b1,s)        => c((b,b1,s))
        case WFormat.DateRange            => dr(())
        case WFormat.Round(b,b1,i)           => r(b,b1,i)
        case WFormat.IntegralRound(b,b1,i)   => sr(b,b1,i)
        case WFormat.Truncate(i)        => t(i)
        case WFormat.Pr1(f)             => pr1(f)
      }))

  type SortDirF = BooleanF

  lazy val sortDirR: Reader[SortDirection, SortDirF] =
    booleanR map (x => if (x) SortDirection.Forward else SortDirection.Reverse)
  lazy val sortDirW: Writer[SortDirection, SortDirF] =
    booleanW cmap ((_:SortDirection) == SortDirection.Forward)

  type SortStrategyF = RepeatF[StringF & SortDirF]
  lazy val sortStrategyR: Reader[SortStrategy, SortStrategyF] = listR(tuple2R(stringR, sortDirR)) map SortStrategy
  lazy val sortStrategyW: Writer[SortStrategy, SortStrategyF] = repeatW(tuple2W(stringW, sortDirW)) cmap {case SortStrategy(pri) => pri}

  lazy val opNelR: Reader[NonEmptyList[Op], NelF[DynamicF]] = nelR(opR)
  lazy val opNelW: Writer[NonEmptyList[Op], NelF[DynamicF]] = nelW(opW)

  type PresentationF = FixF[WFormatF[SelfF]] :: NelF[DynamicF]
  lazy val presentationR: Reader[Presentation, PresentationF] = tuple2R(wformatR, opNelR) map {
    case (f, d) => Presentation(f, d)
  }
  lazy val presentationW: Writer[Presentation, PresentationF] = p2W[WFormat, FixF[WFormatF[SelfF]], NonEmptyList[Op], NelF[DynamicF], Presentation](wformatW, opNelW)(f =>
    {case Presentation(fmt, displayData) => f(fmt, displayData)}
  )

  type LegendColumnsF[F, G] = {
    type λ[A] = RepeatF[S2[A :: F, PresentationF :: SortStrategyF :: G]]
  }
  type LegendHiddenColumns = RepeatF[StringF :: PrimTF :: SortOrderF]
  type LegendF[F, G] = FixF[LegendColumnsF[F, G]#λ[SelfF]] :: LegendHiddenColumns

  def legendR[A,B,F,G](implicit ra: Reader[A, F], rb: Reader[B, G]): Reader[Legend[A, B], LegendF[F, G]] =
    tuple2R(fixFR[LegendColumns[A, B], LegendColumnsF[F, G]#λ](rec =>
              listR(R_\/(tuple2R(rec, ra),
                         tuple3R(presentationR, sortStrategyR, rb)))
                map LegendColumns.apply),
            listR(tuple3R(stringR, primTR, sortOrderR))) map {
      case (is, hs) => Legend(is, hs)
    }

  def legendW[A,B,F,G](implicit wa: Writer[A, F], wb: Writer[B, G]): Writer[Legend[A,B], LegendF[F,G]] =
    tuple2W(fixFW[LegendColumns[A, B], LegendColumnsF[F, G]#λ](rec =>
              repeatW(W_\/(tuple2W(rec, wa),
                           tuple3W(presentationW, sortStrategyW, wb)))
                cmap ((_:LegendColumns[A, B]).inOrder)),
            repeatW(tuple3W(stringW, primTW, sortOrderW))) cmap {
      case Legend(cols, hidden) => (cols, hidden)
    }
}
