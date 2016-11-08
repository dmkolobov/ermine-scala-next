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
  def recordW: Writer[Record, RecordF] =
    repeatW(tuple2W(stringW, primExprW)) cmap ((t: Record) => t.toList)

  type RecordF = RepeatF[StringF & PrimExprF]
  def recordR: Reader[Record, RecordF] =
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
    implicit val peF = primExprRW.reifiedF
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
    implicit val peF = primExprRW.reifiedF
    eitherR(stringR, streamR(recordR)).label("rows").selfDescribing
  }
  unify(rowsW, rowsR)

  private type Projection = Map[Attribute,Op]
  private val projectionRW : CodecPair[Projection] =
    CodecPair[Projection,RepeatF[AttributeF & OpF]](mapR(attributeR,opR))(mapW(attributeW,opW))
  private type ProjectionF = projectionRW.F
  private val projectionR : Reader[Projection,ProjectionF] = projectionRW.R
  private val projectionW : Writer[Projection,ProjectionF] = projectionRW.W

  private type AggProjection = List[(Attribute,AggFunc)]
  private val aggProjectionRW : CodecPair[AggProjection] =
    CodecPair[AggProjection,RepeatF[AttributeF & AggF]](listR(tuple2R(attributeR,aggR)))(repeatW(tuple2W(attributeW,aggW)))
  private type AggProjectionF = aggProjectionRW.F
  private val aggProjectionR = aggProjectionRW.R
  private val aggProjectionW = aggProjectionRW.W

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

  lazy val extRW: CodecPair2[Ext] = {
    type ExtF[MF, RF] =
      S3[relRW.F[MF, RF] & StringF, // ExtRel
         memRW.F[RF, MF],           // ExtMem
         SMF]                       // ExtSM
    new CodecPair2[Ext] {
      type F[M, R] = ExtF[M, R]

      override def W[M, MF, R, RF](wm: Writer[M, MF], wr: Writer[R, RF]) =
        s3W(tuple2W(relW(wm, wr), stringW), memW(wm, wr), smW)((r, m, s) => (ext: Ext[M, R]) => ext match {
          case ExtRel(rel, db) => r((rel, db))
          case ExtMem(mem) => m(mem)
          case ExtSM(sm) => s(sm)
        })

      override def R[M, MF, R, RF](rm: Reader[M, MF], rr: Reader[R, RF]) =
        union3R(p2R(relR(rm, rr), stringR)(ExtRel(_, _)),
                memR(rm, rr).map(ExtMem(_)),
                smR.map(ExtSM(_)))
    }
  }

  def extW[M, MF, R, RF](implicit wm: Writer[M, MF],
                         wr: Writer[R, RF]): Writer[Ext[M, R], extRW.F[MF, RF]] =
    extRW.W(wm, wr)

  def extR[M, MF, R, RF](implicit rm: Reader[M, MF],
                         rr: Reader[R, RF]): Reader[Ext[M, R], extRW.F[MF, RF]] =
    extRW.R(rm, rr)

  type SMF = S2[StringF & StringF, StringF & StringF]

  def smW: Writer[SM, SMF] =
    s2W(tuple2W(stringW,stringW), tuple2W(stringW,stringW))((look, hist) => (sm: SM) => sm match {
      case LookupSM(fld, attr) => look(fld, attr)
      case HistoricalSM(fld, attr) => hist(fld, attr)
    })

  def smR: Reader[SM, SMF] = union2R(p2R(stringR,stringR)(LookupSM(_,_)),
                                          p2R(stringR,stringR)(HistoricalSM(_,_)))

  lazy val memRW: CodecPair2[Mem] = {
    new CodecShape2[Mem] {
      type Shape[RF, MF, A] = S20[
        MF, // VarM
        extRW.F[MF, RF] & memRW.F[RF, MLevelF[RF, MF]], // LetM
        A & PredicateF,                // FilterM
        A & ProjectionF,                  // ProjectM
        A & RepeatF[StringF],             // ExceptM
        A :: AttributeF :: OpF,        // CombineM
        A :: AttributeF :: AggF,          // AggregateM
        A & A,                            // HashInnerJoin
        A & A,                            // MergeOuterJoin
        extRW.F[MF, RF],                  // EmbedMem
        RepeatF[PrimExprF] :: HeaderF :: StringF :: RepeatF[StringF], // ProcedureCall
        RepeatF[RepeatF[StringF & PrimExprF]], // Literal
        HeaderF, // EmptyRel
        A :: RepeatF[AttributeF] :: memRW.F[RF, MLevelF[RF, MF]], // GroupByM
        A :: AttributeF :: StringF :: BooleanF, // RenameM
        A & A,                               // HashLeftJoin
        AttributeF :: AttributeF :: memRW.F[RF, MLevelF[RF, MF]] :: A :: A, // AccumulateM
        ProcessSymbolF & A, // ProcessM
        A :: RepeatF[StringF] :: RepeatF[StringF] :: BooleanF :: FulcrumF, // Pivot
        A // MemoMem
      ]

      override def readShape[R, RF, M, MF, Z](rr: Reader[R, RF], rm: Reader[M, MF]) = { self =>
        union20R(
          rm.map(VarM(_)),
          p2R(extR(rm, rr), memR[R, RF, MLevel[R, M], MLevelF[RF, MF]](mLevelR(rr, rm), rr))(LetM(_, _)),
          p2R(self, predicateR)(FilterM(_, _)),
          p2R(self, projectionR)(ProjectM(_, _)),
          p2R(self, listR(stringR))((a, b) => ExceptM(a, b.toSet)),
          p3R(self, attributeR, opR)(CombineM(_, _, _)),
          p3R(self, attributeR, aggR)(AggregateM(_, _, _)),
          p2R(self, self)(HashInnerJoin(_, _)),
          p2R(self, self)(MergeOuterJoin(_, _)),
          extR(rm, rr).map(EmbedMem(_)),
          p4R(listR(primExprR), headerR, stringR, listR(stringR))(ProcedureCall(_, _, _, _)),
          listR(recordR).map((xs: List[Record]) => Literal(xs.toNel.get)),
          headerR.map(EmptyRel(_)),
          p3R(self, listR(attributeR), memR(mLevelR(rr, rm), rr))(GroupByM.apply),
          p4R(self, attributeR, stringR, booleanR)(RenameM.apply),
          p2R(self, self)(HashLeftJoin.apply),
          p5R(attributeR, attributeR, memR(mLevelR(rr, rm), rr), self, self)(AccumulateM.apply),
          p2R(processSymbolR, self)(ProcessM.apply),
          p5R(self, listR(stringR), listR(stringR), booleanR, fulcrumR)(
            (a,b,c,d,e) => Pivot(a,b.toSet,c.toSet,d,e)),
          self.map(MemoMem.apply)
        )
      }

      override def writeShape[R, RF, M, MF, Z](wr: Writer[R, RF], wm: Writer[M, MF]) = { self =>
        s20W(
          // VarM
          wm
          // LetM
          , tuple2W(extW(wm, wr), memW(mLevelW(wr, wm), wr))
          // FilterM
          , tuple2W(self, predicateW)
          // ProjectM
          , tuple2W(self, projectionW)
          // ExceptM
          , tuple2W(self, repeatW(stringW))
          // CombineM
          , tuple3W(self, attributeW, opW)
          // AggregateM
          , tuple3W(self, attributeW, aggW)
          // HashInnerJoin
          , tuple2W(self, self)
          // MergeOuterJoin
          , tuple2W(self, self)
          // EmbedMem
          , extW(wm, wr)
          // ProcedureCall
          , tuple4W(repeatW(primExprW), headerW, stringW, repeatW(stringW))
          // Literal
          , repeatW(recordW)
          // EmptyRel
          , headerW
          // GroupByM
          , tuple3W(self, repeatW(attributeW), memW(mLevelW(wr, wm), wr))
          // RenameM
          , tuple4W(self, attributeW, stringW, booleanW)
          // HashLeftJoin
          , tuple2W(self, self)
          // AccumulateM
          , tuple5W(attributeW, attributeW, memW[R, RF, MLevel[R,M], MLevelF[RF,MF]](mLevelW(wr, wm), wr), self, self)
          // ProcessM
          , tuple2W(processSymbolW, self)
          // Pivot
          , tuple5W(self, repeatW(stringW), repeatW(stringW), booleanW, fulcrumW)
          // MemoMem
          , self
        )((v, let, fil, pro, exc, com, agg, hashIn, mer, emb, proc, lit, emp, grpBy, ren, hashLeft, accum, process, pivot, memo) =>
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
            case MemoMem(m) => memo(m)
            case QuoteMem(_) => sys.error("Can't serialize a QuoteMem! (it has just a raw object in it.)")
          }
        )
      }
    }.codec2
  }

  def memR[R, RF, M, MF](implicit rm: Reader[M, MF],
                         rr: Reader[R, RF]): Reader[Mem[R, M], memRW.F[RF, MF]] =
    memRW.R(rr, rm)

  def memW[R, RF, M, MF](implicit wm: Writer[M, MF],
                         wr: Writer[R, RF]): Writer[Mem[R, M], memRW.F[RF, MF]] =
    memRW.W(wr, wm)

  val processSymbolRW : CodecPair[ProcessSymbol] = {
    type InternalF = S3[
      AttributeF,              // Median
      AttributeF & AttributeF, // WeightedMean
      AttributeF & AttributeF  // WeightedHarmonicMean
    ]

    CodecPair[ProcessSymbol,InternalF] {
      union3R(
        attributeR.map(Median),
        p2R(attributeR, attributeR)(WeightedMean),
        p2R(attributeR, attributeR)(WeightedHarmonicMean)
      )
    }{
      s3W(
        attributeW,
        tuple2W(attributeW, attributeW),
        tuple2W(attributeW, attributeW)
      )((med, wmean, whmean) => (ps: ProcessSymbol) => ps match {
        case Median(v) => med(v)
        case WeightedMean(w, v) => wmean((w,v))
        case WeightedHarmonicMean(w,v) => whmean((w,v))
      })
    }
  }
  type ProcessSymbolF = processSymbolRW.F
  def processSymbolR: Reader[ProcessSymbol, ProcessSymbolF] = processSymbolRW.R
  def processSymbolW: Writer[ProcessSymbol, ProcessSymbolF] = processSymbolRW.W

  lazy val rLevelRW : CodecPair2[RLevel] =
    new CodecPair2[RLevel] {
      type F[MF, RF] = OptionF[relRW.F[MF, RF]]

      override def W[M, MF, R, RF](wm: Writer[M, MF], wr: Writer[R, RF]) =
        optionW(relW[M,MF,R,RF](wm,wr)) cmap ((x: RLevel[M, R]) => x match {
          case RTop => None
          case RPop(x) => Some(x)
        })

      override def R[M, MF, R, RF](rm: Reader[M, MF], rr: Reader[R, RF]) =
        optionR(relR[M, MF, R, RF](rm,rr)) map {
          case None => RTop
          case Some(x) => RPop(x)
        }
    }
  type RLevelF[MF, RF] = rLevelRW.F[MF,RF]

  def rLevelR[M, MF, R, RF](implicit rm: Reader[M, MF],
                             rr: Reader[R, RF]): Reader[RLevel[M, R], RLevelF[MF, RF]] =
    rLevelRW.R(rm, rr)

  def rLevelW[M, MF, R, RF](implicit wm: Writer[M, MF],
                             wr: Writer[R, RF]): Writer[RLevel[M, R], RLevelF[MF, RF]] =
    rLevelRW.W(wm, wr)

  type MLevelF[RF, MF] = OptionF[memRW.F[RF, MF]]

  def mLevelR[R, RF, M, MF](implicit rr: Reader[R, RF],
                             rm: Reader[M, MF]): Reader[MLevel[R, M], MLevelF[RF, MF]] =
    optionR(memR[R,RF,M,MF]) map {
      case None => MTop
      case Some(x) => MPop(x)
    }

  def mLevelW[R, RF, M, MF](implicit wr: Writer[R, RF],
                             wm: Writer[M, MF]): Writer[MLevel[R, M], MLevelF[RF, MF]] =
    optionW(memW[R,RF,M,MF]) cmap ((x: MLevel[R, M]) => x match {
      case MTop => None
      case MPop(x) => Some(x)
    })

  private val groupByRW : CodecPair[List[Op.ColumnValue]] =
    CodecPair[List[Op.ColumnValue],RepeatF[StringF & PrimTF]](
      listR(p2R(stringR,primTR)(Op.ColumnValue(_,_)))
    )(
      repeatW(p2W(stringW, primTW)(f => (x : Op.ColumnValue) => x match { case Op.ColumnValue(c,v) => f(c,v) }))
    )
  private type GroupByF = groupByRW.F
  private val groupByW = groupByRW.W
  private val groupByR = groupByRW.R

  private type Fulcrum = Map[String,(Record,Op,PrimExpr)]
  lazy val fulcrumRW : CodecPair[Fulcrum] = {
    CodecPair[Fulcrum,RepeatF[StringF :: (RecordF :: OpF :: PrimExprF)]](
      mapR(stringR, tuple3R(recordR, opR, primExprR))
    )(
      mapW(stringW,tuple3W(recordW, opW, primExprW))
    )
  }
  type FulcrumF = fulcrumRW.F
  val fulcrumR : Reader[Fulcrum,FulcrumF] = fulcrumRW.R
  val fulcrumW : Writer[Fulcrum,FulcrumF] = fulcrumRW.W

  lazy val relRW: CodecPair2[Relation] =
    new CodecShape2[Relation] {
      type Shape[MF, RF, A] = S20[
        RF, // Var
        A :: OptionF[IntF] :: OptionF[IntF] :: RepeatF[StringF & BooleanF], // Limit
        extRW.F[MF, RF] & relRW.F[MF, RLevelF[MF, RF]], // Let
        A :: A :: RepeatF[StringF & StringF] :: JoinModeF, // JoinOn
        A & A,    // Union
        A & A,    // Minus
        A & PredicateF, // Filter
        A & ProjectionF, // Project
        A & RepeatF[StringF], // Except
        A :: AttributeF :: OpF, // Combine
        A :: AttributeF :: StringF, // RenameR
        A :: AttributeF :: AggF, // Aggregate
        A :: ProjectionF :: aggProjectionRW.F :: groupByRW.F, // AggregateByGroup
        A :: RepeatF[StringF] :: RepeatF[StringF] :: BooleanF :: FulcrumF, // PivotR
        HeaderF :: (StringF & RepeatF[StringF]), // Table
        RepeatF[S2[StringF & A, PrimExprF]] :: OrderedHeaderF :: StringF :: RepeatF[StringF], // TableProc
        HeaderF, // RelEmpty
        RepeatF[RepeatF[StringF & PrimExprF]], // SmallLit
        A & RepeatF[StringF], // MemoR
        RepeatF[StringF] & A  // Note
      ]

      override def writeShape[M, MF, R, RF, Z](wm: Writer[M, MF], wr: Writer[R, RF]) = { self =>
        s20W(wr, // Var
             tuple4W(self, optionW(intW), optionW(intW), repeatW(tuple2W(stringW, booleanW))), // Limit
             tuple2W(extW(wm, wr), relW(wm, rLevelW(wm, wr))), // Let
             tuple4W(self, self, repeatW(tuple2W(stringW, stringW)), joinModeW), // JoinOn
             tuple2W(self, self), // Union
             tuple2W(self, self), // Minus
             tuple2W(self, predicateW), // Filter
             tuple2W(self, projectionW), // Project
             tuple2W(self, repeatW(stringW)), // Except
             tuple3W(self, attributeW, opW), // Combine
             tuple3W(self, attributeW, stringW), // RenameR
             tuple3W(self, attributeW, aggW), // Aggregate
             tuple4W(self, projectionW, aggProjectionRW.W, groupByRW.W), // AggregateByGroup
             tuple5W(self, repeatW(stringW), repeatW(stringW), booleanW, fulcrumW), // PivotR
             tuple2W(headerW, tuple2W(stringW, repeatW(stringW))), // Table
             tuple4W(repeatW(W_\/(tuple2W(stringW, self), primExprW)), orderedHeaderW, stringW, repeatW(stringW)), // TableProc
             headerW, // RelEmpty
             repeatW(recordW), // SmallLit
             tuple2W(self, repeatW(stringW)), // MemoR
             tuple2W(repeatW(stringW), self) // Note
        )((v, lim, let, on, un, min, fil, proj, exc, comb, ren, agg, group, pivot, tab, tabproc, empt, sl, m, note) =>
          (r: Relation[M, R]) => r match {
            case VarR(x) => v(x)
            case Limit(a, b, c, d) => lim((a, b, c, d.map(p => (p._1, p._2 == Asc)).toList))
            case LetR(a, b) => let((a, b))
            case JoinOn(a, b, c, d) => on((a, b, c, d))
            case Union(a, b) => un(a -> b)
            case Minus(a, b) => min(a -> b)
            case Filter(a, b) => fil(a -> b)
            case Project(a, b) => proj((a, b))
            case Except(a, b) => exc((a, b.toList))
            case Combine(a, b, c) => comb((a, b, c))
            case RenameR(a, b, c) => ren((a, b, c))
            case Aggregate(a, b, c) => agg((a, b, c))
            case AggregateByGroup(a,b,c,d) => group((a,b,c,d))
            case PivotR(a,b,c,d,e) => pivot((a,b,c,d,e))
            case Table(a, b) => tab((a, (b.name, b.schema)))
            case TableProc(a, b, c, d) => tabproc((a, b, c, d))
            case RelEmpty(h) => empt(h)
            case SmallLit(ts) => sl(ts.toList)
            case MemoR(r, pk) => m(r, pk)
            case QuoteR(_) => sys.error("Can't serialize a QuoteR! (it has just a raw object in it.)")
            case Note(ts, under) => note(ts, under)
              // Don't put a catch all here, so we can get compile errors.
          })
      }

      override def readShape[M, MF, R, RF, Z](rm: Reader[M, MF], rr: Reader[R, RF]) = { self =>
        union20R(
          rr.map(VarR(_)),
          p4R(self, optionR(intR), optionR(intR), listR(p2R(stringR, sortOrderR)((_, _))))(Limit(_, _, _, _)),
          p2R(extR(rm, rr), relR(rm, rLevelR(rm, rr)))(LetR(_, _)),
          p4R(self, self, listR(tuple2R(stringR, stringR)) map (_.toSet), joinModeR)(JoinOn(_, _, _, _)),
          p2R(self, self)((a, b) => Union(a, b)),
          p2R(self, self)((a, b) => Minus(a, b)),
          p2R(self, predicateR)((a, b) => Filter(a, b)),
          p2R(self, projectionR)(Project(_, _)),
          p2R(self, listR(stringR))((a, b) => Except(a, b.toSet)),
          p3R(self, attributeR, opR)(Combine(_, _, _)),
          p3R(self, attributeR, stringR)(RenameR(_, _, _)),
          p3R(self, attributeR, aggR)(Aggregate(_, _, _)),
          p4R(self, projectionR, aggProjectionRW.R, groupByRW.R)(AggregateByGroup(_,_,_,_)),
          p5R(self, listR(stringR), listR(stringR), booleanR, fulcrumR)(
            (a,b,c,d,e) => PivotR(a,b.toSet,c.toSet,d,e)),
          p2R(headerR, p2R(stringR, listR(stringR))(TableName(_, _)))(Table(_, _)),
          p4R(listR(R_\/(p2R(stringR, self)((_,_)), primExprR)),
              orderedHeaderR, stringR, listR(stringR))(TableProc(_, _, _, _)),
          headerR.map(RelEmpty(_)),
          listR(recordR).map(xs => SmallLit(xs.toNel.get)),
          p2R(self, listR(stringR))((r, pk) => MemoR(r, pk)),
          p2R(listR(stringR), self)(Note(_, _))
        )
      }
    }.codec2

  def relW[M, MF, R, RF](implicit wm: Writer[M, MF],
                         wr: Writer[R, RF]): Writer[Relation[M, R], relRW.F[MF, RF]] =
    relRW.W(wm, wr)

  def relR[M, MF, R, RF](implicit rm: Reader[M, MF], rr: Reader[R, RF]): Reader[Relation[M, R], relRW.F[MF, RF]] =
    relRW.R(rm, rr)

  lazy val orderedHeaderR: Reader[Header.Ordered, OrderedHeaderF] =
    listR(tuple2R(stringR,primTR))

  lazy val headerR: Reader[Header, HeaderF] = orderedHeaderR map (_.toMap)
  lazy val sourceR: Reader[Source, SourceF] = tuple2R(stringR, listR(stringR)) map {
    case (a, b) => Source(a, b)
  }
  lazy val sourcedR: Reader[Sourced, SourcedF] = tuple2R(listR(sourceR) map (_.toSet), headerR map (_.success))

  lazy val primTRW: CodecPairDynamic[PrimT] = {
    type PrimTF = S9[BooleanF       , // Int
                     BooleanF       , // Byte
                     BooleanF       , // Short
                     BooleanF       , // Long
                     IntF & BooleanF, // String
                     BooleanF       , // Date
                     BooleanF       , // Double
                     BooleanF       , // Boolean
                     BooleanF]        // UUID
    CodecPair.withSelfDescribing[PrimT, PrimTF]{
      union9R(
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
    }{
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
    }
  }
  type PrimTF = primTRW.F
  lazy val primTR: Reader[PrimT, PrimTF] = primTRW.R

  lazy val primExprRW: CodecPairDynamic[PrimExpr] = {
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
    implicit val primtReified = primTRW.reifiedF
    CodecPair.withSelfDescribing[PrimExpr, PrimExprF]{
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
    }{
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
    }
  }
  type PrimExprF = primExprRW.F

  lazy val primExprR: Reader[PrimExpr, PrimExprF] = primExprRW.R

  lazy val predicateRW: CodecPair[Predicate] = {
    type BinOpF = OpF & OpF
    new CodecShape[Predicate] {
      type Shape[A] = S9[BooleanF, BinOpF, BinOpF, BinOpF,
                            A, A & A, A & A, OpF,
                            StringF :: StringF :: RepeatF[StringF] :: RepeatF[OpF]] // Funtest
      override def readShape[Z] = { self =>
        union9R(booleanR map (x => Predicate.Atom(x)),
                p2R(opR, opR)((a, b) => Lt(a, b)),
                p2R(opR, opR)((a, b) => Gt(a, b)),
                p2R(opR, opR)((a, b) => Eq(a, b)),
                self map (was => Not(was)),
                p2R(self, self)((a, b) => Or(a, b)),
                p2R(self, self)((a, b) => And(a, b)),
                opR map IsNull,
                p4R(stringR, stringR, listR(stringR), listR(opR))(Funtest))
      }

      override def writeShape[Z] = { self =>
        s9W(booleanW, // Atom
            tuple2W(opW, opW), // Lt
            tuple2W(opW, opW), // Gt
            tuple2W(opW, opW), // Eq
            self, // Not
            tuple2W(self, self), // Or
            tuple2W(self, self), // And
            opW, // IsNull
            tuple4W(stringW, stringW, repeatW(stringW), repeatW(opW)) // Funtest
        )((atom, lt, gt, eq, not, or, and, isNull, funtest) => (r: Predicate) =>
          r match {
            case Predicate.Atom(x) => atom(x)
            case Lt(x, y) => lt(x -> y)
            case Gt(x, y) => gt(x -> y)
            case Eq(x, y) => eq(x -> y)
            case Not(x) => not(x)
            case Or(x, y) => or(x -> y)
            case And(x, y) => and(x -> y)
            case IsNull(x) => isNull(x)
            case Funtest(n, db, ns, args) => funtest((n, db, ns, args))
          })
      }
    }.codec
  }
  type PredicateF = predicateRW.F

  lazy val predicateR: Reader[Predicate, PredicateF] = predicateRW.R

  lazy val builtinRW: CodecPair[Builtin] =
    CodecPair[Builtin,IntF]{
      intR map {
        case 0 => Upper
        case 1 => Lower
        case 2 => Log
        case 3 => Log10
        case 4 => LogBase
        case 5 => Exp
        case 6 => Abs
        case 7 => Pow
        case 8 => Replace
      }
    } {
      intW cmap ((b: Builtin) => b match {
        case Upper => 0
        case Lower => 1
        case Log => 2
        case Log10 => 3
        case LogBase => 4
        case Exp => 5
        case Abs => 6
        case Pow => 7
        case Replace => 8
      })
    }

  type BuiltinF = builtinRW.F
  lazy val builtinR = builtinRW.R
  lazy val builtinW = builtinRW.W

  lazy val opRW: CodecPair[Op] =
    new CodecShape[Op] {
      type Shape[A] = S16[PrimExprF       , // OpLiteral
                          StringF & PrimTF, // ColumnValue
                          A & A           , // Add
                          A & A           , // Sub
                          A & A           , // Mul
                          A & A           , // FloorDiv
                          A & A           , // DoubleDiv
                          RepeatF[A]      , // Concat
                          PredicateF :: A :: A, // If
                          A & A           , // Coalesce
                          A :: IntF :: IntF , // DateAdd
                          IntF :: A :: A    , // DateDiff
                          StringF :: StringF :: RepeatF[StringF] :: RepeatF[A] :: PrimTF, // Funcall
                          AggF & WindowF , // Windowed
                          BuiltinF & RepeatF[A], // BuiltinCall
                          A & PrimTF          // Cast
                         ]
      override def readShape[Z] = { self =>
        union16R(
          primExprR map OpLiteral,
          p2R(stringR, primTR)(ColumnValue),
          p2R(self, self)((a, b) => Add(a, b)),
          p2R(self, self)((a, b) => Sub(a, b)),
          p2R(self, self)((a, b) => Mul(a, b)),
          p2R(self, self)((a, b) => FloorDiv(a, b)),
          p2R(self, self)((a, b) => DoubleDiv(a, b)),
          listR(self) map (x => Concat(x)),
          p3R(predicateR, self, self)(If),
          p2R(self, self)(Coalesce),
          p3R(self, intR, timeUnitR)(DateAdd),
          p3R(timeUnitR, self, self)(DateDiff),
          p5R(stringR, stringR, listR(stringR), listR(self), primTR)(Funcall),
          p2R(aggR, windowR)(Windowed(_,_)),
          p2R(builtinR,listR(self))(BuiltinCall),
          p2R(self, primTR)(Cast)
        )
      }

      override def writeShape[Z] = { self =>
        lazy val binopW = tuple2W(self, self)
        s16W(primExprW, tuple2W(stringW, primTW), binopW, binopW,
             binopW, binopW, binopW, repeatW(self),
             tuple3W(predicateW, self, self),
             binopW,
             tuple3W(self, intW, timeUnitW),
             tuple3W(timeUnitW, self, self),
             tuple5W(stringW, stringW, repeatW(stringW), repeatW(self), primTW),
             tuple2W(aggW, windowW),
             tuple2W(builtinW, repeatW(self)),
             tuple2W(self,primTW)
        )((opliteral, columnvalue, add, sub, mul, floor, div, cat, oif, coalesce, dateadd, datediff, funcall, windowed, builtin, cast) => (r: Op) => r match {
            case OpLiteral(lit) => opliteral(lit)
            case ColumnValue(cn, ty) => columnvalue(cn -> ty)
            case Add(a, b) => add(a -> b)
            case Sub(a, b) => sub(a -> b)
            case Mul(a, b) => mul(a -> b)
            case FloorDiv(a, b) => floor(a -> b)
            case DoubleDiv(a, b) => div(a -> b)
            case Concat(ss) => cat(ss.toList)
            case If(test, c, a) => oif((test, c, a))
            case Coalesce(l, r) => coalesce(l, r)
            case DateAdd(d, n, u) => dateadd(d, n, u)
            case DateDiff(u, s, e) => datediff(u, s, e)
            case Funcall(n, db, ns, args, ty) => funcall((n, db, ns, args, ty))
            case Windowed(x,y) => windowed((x,y))
            case BuiltinCall(b,xs) => builtin((b,xs))
            case Cast(a,b) => cast((a,b))
          })}
    }.codec

  type OpF = opRW.F
  lazy val opR: Reader[Op, OpF] = opRW.R
  lazy val opW: Writer[Op, OpF] = opRW.W

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

  type JoinModeF = IntF
  lazy val joinModeR: Reader[JoinMode, JoinModeF] = intR map {
    case 0 => JoinMode.Inner
    case 1 => JoinMode.Left
    case 2 => JoinMode.Right
    case 3 => JoinMode.Full
  }
  lazy val joinModeW: Writer[JoinMode, JoinModeF] = intW cmap {
    case JoinMode.Inner => 0
    case JoinMode.Left  => 1
    case JoinMode.Right => 2
    case JoinMode.Full  => 3
  }

  private val frameRW =
    CodecPair[Frame, P2[OptionF[IntF], OptionF[IntF]]] {
      p2R(optionR(intR), optionR(intR))(Frame)
    }{
      p2W(optionW(intW), optionW(intW))(w => { case Frame(b, e) => w(b, e) })
    }
  private type FrameF = frameRW.F
  private val frameW: Writer[Frame, FrameF] = frameRW.W
  private val frameR: Reader[Frame, FrameF] = frameRW.R

  private val windowRW =
    CodecPair[Window, RepeatF[OpF] :: RepeatF[P2[OpF,SortOrderF]] :: FrameF] {
      p3R(listR(opR), listR(tuple2R(opR, sortOrderR)), frameR)(Window)
    }{
      p3W(repeatW(opW), repeatW(tuple2W(opW, sortOrderW)), frameW)(w => {
        case Window(part, ord, frame) => w(part, ord, frame)
      })
    }
  private type WindowF = windowRW.F
  private val windowW: Writer[Window, WindowF] = windowRW.W
  private val windowR: Reader[Window, WindowF] = windowRW.R

  lazy val orderedHeaderW: Writer[Header.Ordered, OrderedHeaderF] =
    repeatW(tuple2W(stringW,primTW))
  lazy val headerW: Writer[Header, HeaderF] = orderedHeaderW cmap ((h: Header) =>
    h.toList)
  lazy val sourceW: Writer[Source, SourceF] = tuple2W(stringW, repeatW(stringW)) cmap ((s: Source) =>
    (s.source, s.namespace))

  lazy val attributeRW : CodecPair[Attribute] = {
    CodecPair[Attribute,StringF & PrimTF](
      p2R(stringR, primTR)(Attribute(_, _))
    )(
      p2W(stringW, primTW)(f => (r: Attribute) => f(r.name, r.t))
    )
  }
  type AttributeF = attributeRW.F
  lazy val attributeW: Writer[Attribute, AttributeF] = attributeRW.W
  lazy val attributeR: Reader[Attribute, AttributeF] = attributeRW.R

  lazy val primTW: Writer[PrimT, PrimTF] = primTRW.W

  lazy val predicateW: Writer[Predicate, PredicateF] = predicateRW.W
  lazy val primExprW: Writer[PrimExpr, PrimExprF] = primExprRW.W

  type OrderedHeaderF = RepeatF[StringF & PrimTF]
  type HeaderF = OrderedHeaderF
  type SourcedF = RepeatF[SourceF] & HeaderF
  type SourceF = P2[StringF, RepeatF[StringF]]
  type BinStringF = StringF & StringF

  lazy val aggRW : CodecPair[AggFunc] = {
    type InternalF =
      S9[UnitF,  // Count
         OpF, // Sum
         OpF, // Avg
         OpF, // Min
         OpF, // Max
         OpF, // Stddev
         OpF, // Variance
         OpF & OpF, // WMean
         OpF & OpF] // WHMean

    CodecPair[AggFunc,InternalF] {
      union9R(
        unitR   map (_ => Count),
        opR map (Sum(_)),
        opR map (Avg(_)),
        opR map (Min(_)),
        opR map (Max(_)),
        opR map (Stddev(_)),
        opR map (Variance(_)),
        p2R(opR,opR)(WMean(_,_)),
        p2R(opR,opR)(WHMean(_,_)))
    }{
      s9W(unitW, opW, opW, opW, opW, opW, opW, tuple2W(opW,opW), tuple2W(opW,opW))(
        (count, sum, avg, min, max, stddev, variance, wmean, whmean) => (agg:AggFunc) => agg match {
           case Count => count(())
           case Sum(e) => sum(e)
           case Avg(e) => avg(e)
           case Min(e) => min(e)
           case Max(e) => max(e)
           case Stddev(e) => stddev(e)
           case Variance(e) => variance(e)
           case WMean(w,e) => wmean(w, e)
           case WHMean(w,e) => whmean(w, e)
        })
    }
  }
  type AggF = aggRW.F
  lazy val aggR: Reader[AggFunc, AggF] = aggRW.R
  lazy val aggW: Writer[AggFunc, AggF] = aggRW.W

  // these should probably be someplace else...
  import scalaz.NonEmptyList
  type NelF[F] = P2[F, RepeatF[F]]
  def nelR[A, F](r: Reader[A, F]): Reader[NonEmptyList[A], NelF[F]] = tuple2R(r, listR(r)) map {
    case (h, t) => NonEmptyList(h, t:_*)
  }

  def nelW[A, F](w: Writer[A, F]): Writer[NonEmptyList[A], NelF[F]] = p2W(w, repeatW(w))(f =>
    (n:NonEmptyList[A]) => f(n.head, n.tail))

  import writers.{Legend, LegendColumns, Presentation, SortDirection,
                  SortStrategy, Format => WFormat, Condition => Condition}

  lazy val conditionRW =
    new CodecShape[Condition] {
      type Shape[A] =
        S6[PrimExprF, // Gt
           PrimExprF, // Lt
           PrimExprF, // Eq
           PrimExprF, // Lte
           PrimExprF, // Gte
           A & A // And
          ]

      override def readShape[Z] = { self =>
        union6R(primExprR map (x => Condition.Gt(x)),
                primExprR map (x => Condition.Lt(x)),
                primExprR map (x => Condition.Eq(x)),
                primExprR map (x => Condition.Lte(x)),
                primExprR map (x => Condition.Gte(x)),
                p2R(self, self)((a, b) => Condition.And(a, b)))
      }

      override def writeShape[Z] = { self =>
        s6W(primExprW, // Gt
            primExprW, // Lt
            primExprW, // Eq
            primExprW, // Lte
            primExprW, // Gte
            tuple2W(self, self) // And
           )((gt, lt, eq, lte, gte, and) => (r: Condition) =>
            r match {
              case Condition.Gt(x) => gt(x)
              case Condition.Lt(x) => lt(x)
              case Condition.Eq(x) => eq(x)
              case Condition.Lte(x) => lte(x)
              case Condition.Gte(x) => gte(x)
              case Condition.And(x,y) => and(x -> y)
            })
      }
    }.codec
  type ConditionF = conditionRW.F
  lazy val conditionR = conditionRW.R
  lazy val conditionW = conditionRW.W

  lazy val wformatRW: CodecPair[WFormat] = new CodecShape[WFormat] {
    type Shape[A] = S14[UnitF, // Default
                       A, // Markdown
                       StringF, // Constant
                       BooleanF :: BooleanF :: IntF :: BooleanF, // Percent
                       BooleanF :: BooleanF :: StringF, // Currency
                       UnitF, // DateRange
                       BooleanF :: BooleanF :: IntF,  // Round
                       BooleanF :: BooleanF :: IntF,  // IntegralRound
                       IntF,  // Truncate
                       A,  // Pr1
                       ConditionF :: A :: A,  // Conditional
                       IntF :: IntF :: A, //Conditional Color
                       RepeatF[StringF & StringF], // Alias
                       UnitF
                     ]
    override def readShape[Z] = { self =>
      union14R(
        unitR   map (_ => WFormat.Default),
        self map (inner => WFormat.Markdown(inner) ),
        stringR map (s => WFormat.Constant(s)),
        p4R(booleanR,booleanR,intR, booleanR)(WFormat.Percentage),
        p3R(booleanR,booleanR,stringR)(WFormat.Currency),
        unitR   map (_ => WFormat.DateRange),
        p3R(booleanR,booleanR,intR)(WFormat.Round),
        p3R(booleanR,booleanR,intR)(WFormat.IntegralRound),
        intR    map (i => WFormat.Truncate(i)),
        self map (inner => WFormat.Pr1(inner)),
        p3R(conditionR,self,self)((c,t,e) => WFormat.Conditional(c,t,e)),
        p3R(colorR,colorR,self)((bg, fg, b) => WFormat.ColorFormat(bg, fg, b)),
        listR(tuple2R(stringR, stringR)) map (WFormat.Alias),
        unitR map (_ => WFormat.Verbatim)
        )
    }

    override def writeShape[Z] = { self =>
        s14W(unitW, self, stringW, tuple4W(booleanW, booleanW, intW, booleanW),
             tuple3W(booleanW,booleanW,stringW), unitW, tuple3W(booleanW,booleanW,intW),
             tuple3W(booleanW,booleanW,intW), intW, self, tuple3W(conditionW, self, self),
             tuple3W(colorW, colorW, self), repeatW(tuple2W(stringW,stringW)), unitW)(
          (d, md, k, p, c, dr, r, sr, t, pr1, cond, color, alias, vbt) => (w: WFormat) => w match {
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
            case WFormat.Conditional(c,t,e) => cond(c,t,e)
            case WFormat.ColorFormat(bg, fg, b) => color(bg, fg, b)
            case WFormat.Alias(als) => alias(als)
            case WFormat.Verbatim => vbt(())
          })
    }
  }.codec

  lazy val wformatR = wformatRW.R

  lazy val wformatW = wformatRW.W

  type SortDirF = BooleanF

  lazy val sortDirR: Reader[SortDirection, SortDirF] =
    booleanR map (x => if (x) SortDirection.Forward else SortDirection.Reverse)
  lazy val sortDirW: Writer[SortDirection, SortDirF] =
    booleanW cmap ((_:SortDirection) == SortDirection.Forward)

  type SortStrategyF = RepeatF[StringF & SortDirF]
  lazy val sortStrategyR: Reader[SortStrategy, SortStrategyF] = listR(tuple2R(stringR, sortDirR)) map SortStrategy
  lazy val sortStrategyW: Writer[SortStrategy, SortStrategyF] = repeatW(tuple2W(stringW, sortDirW)) cmap {case SortStrategy(pri) => pri}

  lazy val opNelR: Reader[NonEmptyList[Op], NelF[OpF]] = nelR(opR)
  lazy val opNelW: Writer[NonEmptyList[Op], NelF[OpF]] = nelW(opW)

  type PresentationF = wformatRW.F :: NelF[OpF]
  lazy val presentationR: Reader[Presentation, PresentationF] = tuple2R(wformatR, opNelR) map {
    case (f, d) => Presentation(f, d)
  }
  lazy val presentationW: Writer[Presentation, PresentationF] = p2W[WFormat, wformatRW.F, NonEmptyList[Op], NelF[OpF], Presentation](wformatW, opNelW)(f =>
    {case Presentation(fmt, displayData) => f(fmt, displayData)}
  )

  // Why this alias isn't in f0, I have no idea.
  type OptionF[F] = S2[UnitF,F]

  type LegendColumnsF[F, G] = {
    type λ[A] = RepeatF[S2[A :: F, PresentationF :: SortStrategyF :: G]]
  }
  type LegendHiddenColumns = RepeatF[StringF :: PrimTF :: SortOrderF]
  type LegendF[F, G] = FixF[LegendColumnsF[F, G]#λ[SelfF]] :: LegendHiddenColumns :: OptionF[StringF :: PrimTF]

  def legendR[A,B,F,G](implicit ra: Reader[A, F], rb: Reader[B, G]): Reader[Legend[A, B], LegendF[F, G]] =
    tuple3R(fixFR[LegendColumns[A, B], LegendColumnsF[F, G]#λ](rec =>
              listR(R_\/(tuple2R(rec, ra),
                         tuple3R(presentationR, sortStrategyR, rb)))
                map LegendColumns.apply),
            listR(tuple3R(stringR, primTR, sortOrderR)),
            optionR(tuple2R(stringR, primTR))) map {
      case (is, hs, gc) => Legend(is, hs, gc)
    }

  def legendW[A,B,F,G](implicit wa: Writer[A, F], wb: Writer[B, G]): Writer[Legend[A,B], LegendF[F,G]] =
    tuple3W(fixFW[LegendColumns[A, B], LegendColumnsF[F, G]#λ](rec =>
              repeatW(W_\/(tuple2W(rec, wa),
                           tuple3W(presentationW, sortStrategyW, wb)))
                cmap ((_:LegendColumns[A, B]).inOrder)),
            repeatW(tuple3W(stringW, primTW, sortOrderW)),
            optionW(tuple2W(stringW, primTW))) cmap {
      case Legend(cols, hidden, gc) => (cols, hidden, gc)
    }
}
