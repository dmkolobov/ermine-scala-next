package com.clarifi.reporting
package writers

import writers.{Markdown => MarkdownParser}

import collection.immutable.IndexedSeq
import runtime.{AbstractFunction1 => abs_=>}

import scalaz.{
  \/, -\/, \/-, ==>>, Applicative, Bifoldable, Bifunctor, Bitraverse,
  Equal, Functor, LensFamily, Monad, Monoid, NonEmptyList, Order,
  Ordering, Semigroup, State, Traverse
}
import scalaz.Lens.mapVLens
import State.state
import scalaz.WriterT.writerMonad
import scalaz.std.anyVal._
      ,scalaz.std.function.fix
      ,scalaz.std.indexedSeq._
      ,scalaz.std.list._
      ,scalaz.std.option._
      ,scalaz.std.set._
      ,scalaz.std.string._
      ,scalaz.std.tuple._
import scalaz.syntax.applicative.{ToFunctorOps => _, ToFunctorOpsUnapply => _, _}
      ,scalaz.syntax.bitraverse._
      ,scalaz.syntax.id._
      ,scalaz.syntax.monoid._
      ,scalaz.syntax.order._
      ,scalaz.syntax.std.boolean._
      ,scalaz.syntax.std.list._
      ,scalaz.syntax.std.option._
      ,scalaz.syntax.std.vector._
      ,scalaz.syntax.traverse._

/** Label and order information for a particular ρ type.
  *
  * @param inOrder
  *
  * @tparam Grp The group identifiers.
  * @tparam Lbl The functor's abstract value of leaf identifiers.
  *     Certain operations, like `deriveSort`, expect this to obey
  *     equality and hashing laws.  `orderedPresentations` may contain
  *     duplicates, but this might not mean something you like.
  */
case class Legend[Grp, Lbl](inOrder: LegendColumns[Grp, Lbl],
                            undisplayed: Seq[(ColumnName, PrimT, SortOrder)])
     extends TraversableColumns[Legend[Grp, Lbl]] {
  assert(leavesInOrder forall {case (pr, sortBy, _) =>
           pr.columnReferences === sortBy.columnReferences},
         "sortBy must completely describe displayData")

  def append(right: Legend[Grp, Lbl]): Legend[Grp, Lbl] =
    Legend(inOrder append right.inOrder, undisplayed ++ right.undisplayed)

  def labels: Seq[Lbl] = leavesInOrder.view.map(_._3)
  def formats = leavesInOrder.map( _._1.format)

  def leavesInOrder: Seq[(Presentation, SortStrategy, Lbl)] = inOrder.leavesInOrder

  /** Squash away all groups. */
  def groupless[G]: Legend[G, Lbl] = Legend(inOrder.groupless, undisplayed)

  /** Wrap columns in a single column `group`. */
  def columnGroup(group: Grp): Legend[Grp, Lbl] =
    copy(inOrder = LegendColumns(Vector(-\/(inOrder, group))))

  def orderedPresentations: Seq[(Presentation, Lbl)] =
    leavesInOrder.view map {case (p, _, l) => (p, l)}

  /** In-order traversal of columns described by this legend. */
  def traverseColumns[F[_]: Applicative](f: ColumnName => F[ColumnName]): F[Legend[Grp, Lbl]] = {
    val inOrderF = inOrder traverseColumns f
    val undisplayedF = undisplayed.toList.traverse {
      case (col, pt, so) => f(col) map (c => (c, pt, so))
    }
    ^(inOrderF, undisplayedF)(Legend.apply)
  }

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z = {
    val inOrderZ = inOrder typedColumnFoldMap f
    val undisplayedZ = undisplayed.toIndexedSeq foldMap {case (col, pt, _) => f(col, pt)}
    inOrderZ |+| undisplayedZ
  }

  /** Legend is bitraversable. */
  def bitraverse[F[_]: Applicative, C, D](f: Grp => F[C], g: Lbl => F[D])
      : F[Legend[C, D]] =
    inOrder bitraverse (f, g) map (s => Legend(s, undisplayed))

  private[this] def sortRules: Map[Lbl, List[SortStrategy]] =
    (leavesInOrder groupBy (_._3) mapValues (_ map (_._2) toList))

  /** As with `deriveSort`, but don't flatten the results to relational
    * columns.  This doesn't exclude any presentation sorts based on
    * prior *column* appearances; it only cares about prior *label*
    * appearances, whereas `deriveSort` handles this for you.
    *
    * @return The undisplayed columns, to be prioritized, and the
    *         selected `Presentation`s and `SortStrategy`s.
    */
  def selectSort(viewSorts: TraversableOnce[(Lbl, SortOrder)])
                (implicit Lbl: Order[Lbl])
      : (IndexedSeq[(ColumnName, SortOrder)],
         IndexedSeq[(Presentation, SortOrder, SortStrategy)]) = {
    import scalaz.std.iterable._, Legend._
    (undisplayed.map(t => (t._1, t._3)).toIndexedSeq,
     viewSorts.foldLeft((Vector.empty[(Presentation, SortOrder, SortStrategy)],
                         leavesInOrder foldMap {case (p, ss, l) =>
                           ==>>(l -> NonEmptyList((p, ss)))})){(st, srt) =>
       val ((res, unused), (lbl, viewOrder)) = (st, srt)
       val (found, unused2) =
         unused updateLookupWithKey (lbl, (_, lp) => lp.tail.toNel)
       found.fold(st){case NonEmptyList((pr, ss), _*) =>
         (res :+ ((pr, viewOrder, ss)), unused2)}
     }._1)
  }

  /** Find the sort to be applied to the underlying relations I
    * describe, according to a sort specified in terms of labels.
    *
    * @see [[com.clarifi.reporting.writers.TestLegend]]
    */
  def deriveSort(viewSorts: TraversableOnce[(Lbl, SortOrder)]
               ): IndexedSeq[(ColumnName, SortOrder)] = {
    val st = (undisplayed.map(t => (t._1, t._3)).toIndexedSeq,
              Set.empty[ColumnName], sortRules)

    viewSorts.foldLeft(st) {(st, srt) =>
      val ((colsorts, seencols, unusedPresents), (lbl, viewOrder)) = (st, srt)
      unusedPresents getOrElse (lbl, Nil) match {
        case Nil => (colsorts, seencols, unusedPresents)
        case sortBy :: rightLabeled =>
          // flip and mark the cols we're not already sorting by
          val absSort = sortBy(viewOrder) filterNot (_._1 |> seencols)
          (colsorts ++ absSort,
           // remember these cols so we don't sort again
           seencols | sortBy.columnReferences,
           // drop sortBy
           unusedPresents + (lbl -> rightLabeled))
      }
    } _1
  }

  /** Canonicalize a sort, by removing entries that I won't use.
    *
    * @note ∀s. `deriveSort(filterSort(s.toSeq))` ≡ `deriveSort(s)` */
  def filterSort(viewSort: Seq[(Lbl, SortOrder)]): IndexedSeq[(Lbl, SortOrder)] =
    Vector(viewSort:_*).filterM[State[Map[Lbl, Int], ?]]{case (lbl, _) =>
      val clbl = mapVLens[Lbl, Int](lbl).xmapB(identity)((_:Option[Int]) filter (0<))
      clbl flatMap (_ >| ((clbl %= (_ map (_-1))) >| true) | state(false))
    } eval sortRules.mapValues(_.size)

  /** Answer a default sort of all columns, left to right. */
  def leftToRightSort: IndexedSeq[(Lbl, SortOrder)] =
    labels.map(_ -> SortOrder.Asc).toIndexedSeq

  /** Every step of `basicEval` except the `Format` application step.
    * This controls custom formatting.
    */
  def liftFormatEvaluator[A](f: Format => NonEmptyList[PrimExpr] => A) : Record => IndexedSeq[A] = {
        val kvm = inOrder.leavesInOrder map {case (pr, _, _) => (pr, f(pr.format))}
        t => kvm map {case (pr, ev) => ev(pr extract t)}
  }

  /** The built-in evaluation strategy for legends.  Legends consist
    * entirely of data, so this strategy may be displaced by
    * alternatives, such as a writer-specific presentation
    * interpreter.
    */
  lazy val basicEval: Record => IndexedSeq[PrimExpr] =
    liftFormatEvaluator(_.basicEval)

  lazy val basicEvalWithFormat: Record => IndexedSeq[(PrimExpr, Format)] =
    r => basicEval(r).zip(formats)
}

object Legend {
  /** Legend with same group and leaf label type. */
  type U[A] = Legend[A, A]

  /** An extractor for the leaves. */
  object Leaves {
    def unapply[Grp, Lbl](lg: Legend[Grp, Lbl])
        : Some[Seq[(Presentation, SortStrategy, Lbl)]] =
      Some(lg.leavesInOrder)
  }

  def columnsL[G1, G2, L1, L2]: LensFamily[Legend[G1, L1], Legend[G2, L2],
                                           LegendColumns[G1, L1], LegendColumns[G2, L2]] =
    LensFamily lensFamilyu ((lg, lc) => lg copy (inOrder = lc), _.inOrder)

  /** Add a legend to a presentation. */
  def overPresentation[Grp, Lbl](p: Presentation, label: Lbl): Legend[Grp, Lbl] =
    Legend(LegendColumns flat (IndexedSeq((p, SortStrategy allForward p.columnReferencesList.distinct,
                                           label))),
           IndexedSeq.empty)

  /** Add a legend to a presentation, with ordering.  Convenient for
    * Ermine. */
  def overPresentation[Grp, Lbl](p: Presentation, sort: List[(ColumnName, SortDirection)],
                            label: Lbl): Legend[Grp, Lbl] =
    Legend(LegendColumns flat (IndexedSeq((p, SortStrategy(sort), label))),
           IndexedSeq.empty)

  /** Convenient for Ermine. */
  def umap[A, B](lg: U[A])(f: A => B): U[B] = lg umap f

  def hiding[G, L](op: Op, ss: SortStrategy, sp: Option[(SortOrder, Int)])
      : Legend[G, L] = {
    val typedColRefsMap = op.typedColumnReferencesList.toMap
    Legend(
      LegendColumns.empty,
      sp.map(soi => ss(soi._1)).getOrElse(Nil) collect {
        case (c, so) if typedColRefsMap.contains(c) =>
          (c, typedColRefsMap(c), so)
      }
    )
  }

  /** The empty legend. */
  def empty[Grp, Lbl] = Legend[Grp, Lbl](LegendColumns.empty, IndexedSeq.empty)

  /** Legend is a bifunctor. */
  implicit val LegendBifunctor: Bifunctor[Legend] = new Bifunctor[Legend] {
    def bimap[A, B, C, D](r: Legend[A, B])(f: A => C, g: B => D) =
      Legend(r.inOrder bimap (f, g), r.undisplayed)
  }

  /** Legend is a monoid. */
  implicit def LegendMonoid[Grp, Lbl]: Monoid[Legend[Grp, Lbl]] =
    Monoid instance ((a, b) => a append b, Legend.empty)

  /** Legends can be equal. */
  implicit def LegendEqual[Grp: Equal, Lbl: Equal]: Equal[Legend[Grp, Lbl]] = {
    import scalaz.std.iterable._
    Equal equalBy (lg => (lg.inOrder, lg.undisplayed))
  }

  /** The legend that only picks columns in a particular order. */
  def select[A](cols: Seq[ColumnName], h: ColumnName => PrimT): Legend[A, ColumnName] =
    Legend(LegendColumns flat (
             cols map (c => (Presentation.unit(NonEmptyList(c -> h(c))),
                            SortStrategy allForward IndexedSeq(c),
                            c))),
           IndexedSeq.empty)

  /** @todo Remove for scalaz 7.1 port. */
  private implicit def tmpMapUnion[A, B](implicit A: Order[A], B: Semigroup[B]): Monoid[A ==>> B] =
    Monoid.instance((l, r) => (l unionWith r)(B.append(_, _)), ==>>.empty)
}

/** The visible portion of a `Legend`. */
final case class LegendColumns[Grp, Lbl](
    inOrder: Seq[(LegendColumns[Grp, Lbl], Grp)
                 \/ (Presentation, SortStrategy, Lbl)])
  extends TraversableColumns[LegendColumns[Grp, Lbl]] {
  import LegendColumns.outCovariant

  def append(right: LegendColumns[Grp, Lbl]): LegendColumns[Grp, Lbl] =
    LegendColumns(inOrder ++ right.inOrder)

  def bimap[C, D](f: Grp => C, g: Lbl => D): LegendColumns[C, D] =
    LegendColumns(inOrder map (_ bimap (_ bimap (_ bimap (f, g), f), _ map g)))

  private def traverseGroupsLeaves[F[_]: Applicative, C, D]
    (f: Grp => F[C],
     g: ((Presentation, SortStrategy, Lbl)) => F[(Presentation, SortStrategy, D)])
      : F[LegendColumns[C, D]] =
    (outCovariant
       .bitraverse(inOrder.toIndexedSeq)
                  (_ bitraverse (_ traverseGroupsLeaves (f, g), f))
                  (g)
       map LegendColumns.apply)

  def bitraverse[F[_]: Applicative, C, D](f: Grp => F[C], g: Lbl => F[D]): F[LegendColumns[C, D]] =
    traverseGroupsLeaves(f, _ traverse g)

  /** Traverse the rights of `inOrder`. */
  def traverseLeaves[F[_]: Applicative, C](f: ((Presentation, SortStrategy, Lbl)) => F[(Presentation, SortStrategy, C)]): F[LegendColumns[Grp, C]] =
    traverseGroupsLeaves(_.point[F], f)

  /** `traverseLeaves` with the const applicative. */
  def leavesInOrder: IndexedSeq[(Presentation, SortStrategy, Lbl)] =
    traverseLeaves[λ[α => IndexedSeq[(Presentation, SortStrategy, Lbl)]],
                   Nothing](IndexedSeq(_))

  /** Squash away all groups. */
  def groupless[G]: LegendColumns[G, Lbl] =
    LegendColumns(leavesInOrder map \/.right)

  /** Applicative filter. */
  def collectA[F[_]: Applicative, L](f: ((Presentation, SortStrategy, Lbl))
                                     => F[Option[(Presentation, SortStrategy, L)]])
    : F[LegendColumns[Grp, L]] =
    (outCovariant
       .bitraverse(inOrder.toIndexedSeq)
                  (_ bitraverse (_ collectA f, _.point[F]))
                  (f)
       map (v => LegendColumns(v collect {case l@ -\/(_) => l
                                         case \/-(Some(r)) => \/-(r)})))

  /** Remove empty groups, groups containing only empty groups, &c. */
  def pruneGroups: LegendColumns[Grp, Lbl] = {
    def rec(lg: LegendColumns[Grp, Lbl]): Option[LegendColumns[Grp, Lbl]] = {
      val pruned = lg.inOrder
        .collect(Function.unlift(Bitraverse[\/].leftTraverse.traverse
                                   (_)(sg => rec(sg._1) map ((_, sg._2)))))
      pruned.nonEmpty option LegendColumns(pruned)
    }
    rec(this) getOrElse LegendColumns.empty
  }

  def traverseColumns[F[_]: Applicative](f: ColumnName => F[ColumnName]): F[LegendColumns[Grp, Lbl]] =
    traverseGroupsLeaves(_.point[F], {case (prs, sortBy, lbl) =>
      ^(prs traverseColumns f, sortBy traverseColumns f)((_, _, lbl))})

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
    (outCovariant
       .bifoldMap(inOrder.toIndexedSeq)
                 (Bifoldable[Tuple2].leftFoldable.foldMap(_)(_ typedColumnFoldMap f))
                 {case (pr, ss, _) =>
                   (pr typedColumnFoldMap f) |+| (ss typedColumnFoldMap f)})
}

object LegendColumns {
  import util.Bifunctors._

  type Out[Grp, Lbl] =
    Seq[(LegendColumns[Grp, Lbl], Grp) \/ (Presentation, SortStrategy, Lbl)]

  def outL[G1, G2, L1, L2]: LensFamily[LegendColumns[G1, L1], LegendColumns[G2, L2],
                                       Out[G1, L1], Out[G2, L2]] =
    LensFamily lensFamilyu ((lc, o) => lc copy (inOrder = o), _.inOrder)

  val outCovariant = Traverse[IndexedSeq].bicompose[\/]

  /** The monoid's zero. */
  def empty[G, L]: LegendColumns[G, L] = LegendColumns(IndexedSeq.empty)

  implicit val LegendColumnsCovariant: Bitraverse[LegendColumns] =
    new Bitraverse[LegendColumns] {
      override def bimap[A, B, C, D](r: LegendColumns[A, B])(f: A => C, g: B => D) =
        r bimap (f, g)

      def bitraverseImpl[G[_] : Applicative, A, B, C, D]
        (r: LegendColumns[A, B])(f: A => G[C], g: B => G[D]) =
        r bitraverse (f, g)
    }

  def flat[G, Lbl](inOrder: Seq[(Presentation, SortStrategy, Lbl)])
      : LegendColumns[G, Lbl] = LegendColumns(inOrder map \/.right)

  /** `LegendColumns` is a monoid. */
  implicit def LegendColumnsMonoid[Grp, Lbl]: Monoid[LegendColumns[Grp, Lbl]] =
    Monoid instance ((a, b) => a append b, empty)

  @inline private[this]
  def fixEq[A](f: Equal[A] => Equal[A]): Equal[A] =
    fix[Equal[A]](rec => f(Equal equal ((a, b) => rec equal (a, b))))

  /** `LegendColumns`s can be equal. */
  implicit def LegendColumnsEqual[G: Equal, L: Equal]: Equal[LegendColumns[G, L]] =
    fixEq(implicit rec => Equal.equalBy(_.inOrder.toIndexedSeq))
}

/** The priority and *relative* order of a series of columns. */
case class SortStrategy(priority: Seq[(ColumnName, SortDirection)])
     extends (SortOrder => IndexedSeq[(ColumnName, SortOrder)])
     with TraversableColumns[SortStrategy] {
  def traverseColumns[F[_]: Applicative](f: ColumnName => F[ColumnName]): F[SortStrategy] =
    priority.toList traverse {case (cn, sd) => f(cn) map (_ -> sd)} map SortStrategy

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
    mzero[Z]

  def apply(o: SortOrder): IndexedSeq[(ColumnName, SortOrder)] =
    (priority.view map (_ map (o |>)) toIndexedSeq)

  override def toString = "SortStrategy(%s)" format priority
}

object SortStrategy extends (Seq[(ColumnName, SortDirection)] => SortStrategy) {
  /** Constructor for priority-only. */
  def allForward(cols: Seq[ColumnName]): SortStrategy =
    SortStrategy(cols map (_ -> SortDirection.Forward))

  /** Easier to call from Ermine. */
  def fromList(priority: List[(ColumnName, SortDirection)]): SortStrategy =
    SortStrategy(priority)

  implicit val sortStrategyInstance: Order[SortStrategy] = new Order[SortStrategy] {
    def order(l: SortStrategy, r: SortStrategy) =
      l.priority.toIndexedSeq ?|? r.priority.toIndexedSeq
    override def equal(l: SortStrategy, r: SortStrategy) =
      l.priority.toIndexedSeq === r.priority.toIndexedSeq
    override def equalIsNatural = false
  }
}

/** Whether an Op reverses the sort order of its underlying relational
  * field. */
sealed abstract class SortDirection extends (SortOrder => SortOrder) {
  import SortOrder.{Asc, Desc}
  import SortDirection._

  /** Vary `a` according to how I perceive it, relatively. */
  def apply(a: SortOrder) = (a, this) match {
    case (Asc, Forward) | (Desc, Reverse) => Asc
    case (Asc, Reverse) | (Desc, Forward) => Desc
  }
}

object SortDirection {
  case object Forward extends SortDirection {
    override def toString = "Forward"
  }
  case object Reverse extends SortDirection {
    override def toString = "Reverse"
  }

  implicit val sortDirectionInstance: Order[SortDirection] = new Order[SortDirection] {
    def order(l: SortDirection, r: SortDirection) = (l, r) match {
      case (Forward, Reverse) => Ordering.LT
      case (Reverse, Forward) => Ordering.GT
      case _ => Ordering.EQ
    }
    override def equal(l: SortDirection, r: SortDirection) = l == r
    override def equalIsNatural = true
  }
}

/** Non-codata description of how to display fields, so that writers
  * can reinterpret them for their media. */
final case class Presentation(format: Format,
                              displayData: NonEmptyList[Op])
      extends TraversableColumns[Presentation] {
  def traverseColumns[F[_]: Applicative](f: ColumnName => F[ColumnName]): F[Presentation] =
    displayData traverse (_ traverseColumns f) map (Presentation(format, _))

  /** Extract raw data suitable for `format.basicEval`. */
  def extract(t: Record): NonEmptyList[PrimExpr] = displayData map (_ eval t)

  /** The built-in evaluation strategy for presentations. */
  def basicEval: Record => PrimExpr = format.basicEval compose extract

  def postReplaceOp[F[_]: Monad](f: Op => F[Op]): F[Presentation] =
    displayData traverse (_ postReplace f) map (Presentation(format, _))

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z =
    displayData foldMap (_ typedColumnFoldMap f)
}

object Presentation
       extends ((Format, NonEmptyList[Op]) => Presentation) {
  /** Alias, more convenient to call from DMTL. */
  def oneOp(fmt: Format, op: Op) =
    Presentation(fmt, NonEmptyList(op))

  /** Alias, more convenient to call from DMTL. */
  def twoOps(fmt: Format, op1: Op, op2: Op) =
    Presentation(fmt, NonEmptyList(op1, op2))

  /** The presentation that does nothing.  Use `basicPresentation` in
    * DMTL instead. */
  def unit(cols: NonEmptyList[(ColumnName, PrimT)]): Presentation =
    Presentation(Format.Default, cols map Op.ColumnValue.tupled)

  /** Just show `disp` as-is. */
  def constant(disp: PrimExpr): Presentation =
    Presentation(Format.Default, NonEmptyList(Op.OpLiteral(disp)))

  /** Strip away the niceties of the `Presentation` and leave something
    * half-broken in its place.  See `Format#devolve`.
    */
  def devolve(pr: Presentation): Op = pr.format devolve pr.displayData

  /** Silly coercion function, working with Ops, Predicates, and of
    * course Presentations. */
  def coerceFrom(a: Any): Option[Presentation] = a match {
    case a: Presentation => Some(a)
    case a: Op =>
      Some(Presentation(Format.Default, NonEmptyList(a)))
    case a: Predicate => coerceFrom(Op.If(a, Op.OpLiteral(BooleanExpr(false, true)),
                                         Op.OpLiteral(BooleanExpr(false, false))))
    case _ => None
  }

  implicit val presentationInstance: Equal[Presentation] = Equal.equalA
}

/**
 * Condition:
 *    a) single conditions: (>, <, =, >=, <=) (PrimExpr)
 *    b) And conditions*/
sealed abstract class Condition {
  def apply(e: PrimExpr): Boolean
}

object Condition {
  case class Gt(comparator: PrimExpr) extends Condition {
    override def apply(e: PrimExpr): Boolean = e > comparator
  }
  case class Lt(comparator: PrimExpr) extends Condition {
    override def apply(e: PrimExpr): Boolean = e < comparator
  }
  case class Eq(comparator: PrimExpr) extends Condition {
    override def apply(e: PrimExpr): Boolean = e == comparator
  }
  case class Gte(comparator: PrimExpr) extends Condition {
    override def apply(e: PrimExpr): Boolean = e >= comparator
  }
  case class Lte(comparator: PrimExpr) extends Condition {
    override def apply(e: PrimExpr): Boolean = e <= comparator
  }
  case class And(c1: Condition, c2: Condition) extends Condition {
    override def apply(e: PrimExpr): Boolean = c1(e) && c2(e)
  }
}

/** Fixed, field-independent description of how to format a field. */
sealed trait Format {
  /** Homomorphism of evaluation results to PrimExprs displayed as
    * with `Default`, for this Format. */
  def basicEval: NonEmptyList[PrimExpr] => PrimExpr

  /** As well as possible, simplify this format into an `Op`
    * homomorphism.
    */
  def devolve(ops: NonEmptyList[Op]): Op

  /** Law: basicEval === recursiveEval(_.basicEval)
    *
    */
  def recursiveEval(rec: Format => NonEmptyList[PrimExpr] => PrimExpr): NonEmptyList[PrimExpr] => PrimExpr = basicEval
}

object Format {
  import ReportingUtils.{threadLocal => tlv}
  import Op._
  import PrimExprs.formatDate
  import PrimT.{DateT, DoubleT, LongT, IntT, ShortT, ByteT}
  import java.text.{
    MessageFormat => ThreadUnsafeMessageFormat,
    NumberFormat => ThreadUnsafeNumberFormat,
    DecimalFormat
  }
  import java.util.{Currency => JCurrency, Locale}
  import java.awt.Color

  private type NelPe = NonEmptyList[PrimExpr]
  private type NelOp = NonEmptyList[Op]

//add style transform...

  private def negParenTransform(useColor: Boolean, doIt: Boolean, fmt : ThreadUnsafeNumberFormat) : ThreadUnsafeNumberFormat = {
    var res1 =
     if(doIt)
       (fmt match {
          case df:DecimalFormat => {
               df.setNegativePrefix("("+df.getPositivePrefix)
               df.setNegativeSuffix(df.getNegativeSuffix+")")
               df.setPositiveSuffix(df.getPositiveSuffix+"\u2008")
               df
             }
          case f => f})
      else fmt
   if(useColor)
       (res1 match {
          case df:DecimalFormat => {
               df.setNegativePrefix("<NEGATIVE>"+df.getNegativePrefix)
               df.setNegativeSuffix(df.getNegativeSuffix+"</NEGATIVE>")
               df.setPositivePrefix("<POSITIVE>"+df.getPositivePrefix)
               df.setPositiveSuffix(df.getPositiveSuffix+"</POSITIVE>")
               df
             }
          case f => f})
   else res1
  }


  /** Adapt a NumberFormat source to a basicEval. */
  private def numberFormatEval(fmt: ThreadLocal[ThreadUnsafeNumberFormat]): NelPe => PrimExpr =
    (pes: NelPe) => pes.head match {
      case ByteExpr(n, v)   => StringExpr(n, fmt.get format v)
      case ShortExpr(n, v)  => StringExpr(n, fmt.get format v)
      case IntExpr(n, v)    => StringExpr(n, fmt.get format v)
      case LongExpr(n, v)   => StringExpr(n, fmt.get format v)
      case DoubleExpr(n, v) => StringExpr(n, fmt.get format v)
      case pe => pe
    }

  /** Round a DoubleT-typed op to `places`. */
  private def roundOp(places: Int, op: Op): Op =
    // 18 is the greatest n for which 10ⁿ is Long-representable.
    if (places <= 0 || places > 18) op else {
      val shift = OpLiteral(DoubleExpr(false, math.pow(10, places)))
      DoubleDiv(FloorDiv(Add(Mul(op, shift),
                             OpLiteral(DoubleExpr(false, 0.5))),
                         OpLiteral(DoubleExpr(false, 1))),
                shift)
    }

  def negParenOp(op : Op) = If(Predicate.Lt(op,OpLiteral(IntExpr(false,0))),
                               Concat(List(OpLiteral(StringExpr(false,"(")),Mul(op,OpLiteral(IntExpr(false,-1))),OpLiteral(StringExpr(false,")")))),
                               op)


  /** Use whatever the default formatting for the Op type seems to
    * be. */
  case object Default extends Format {
    val basicEval = (_: NelPe).head

    def devolve(ops: NelOp) = ops.head
  }

  /** like Default, but should interpret + apply markdown formatting
    * to strings. Markdown is already taken by an object associated with the markdown parser,
    * so call it MarkdownFmt to disambiguate */
  case class Markdown( wrapped: Format ) extends Format {
    val basicEval = recursiveEval(_.basicEval)

    def devolve(ops: NelOp) = wrapped.devolve(ops)

    override def recursiveEval(rec: Format => NelPe => PrimExpr) = wrapped match {
      case Truncate(places) => (pes: NelPe) => pes.head match {
        case StringExpr(n, v) => {
          assert(places >= 0)
          StringExpr(n,MarkdownParser.truncateMarkdown(v,places))
        }
        case pe => pe
      }
      case _ => rec(wrapped)
    }
  }

  /** Constant format that always returns a given string. */
  case class Constant(value: String) extends Format {
    val basicEval = (_: NelPe) => StringExpr(false, value)
    def devolve(ops: NelOp) = OpLiteral(StringExpr(false, value))
  }

  /** Format as a percentage, where numeric 1 displays as "100%". */
  case class Percentage(useColor: Boolean, doNegParens: Boolean, places: Int, pad: Boolean) extends Format {
    val basicEval = numberFormatEval(tlv{
      val formatter = ThreadUnsafeNumberFormat.getPercentInstance
      formatter.setMinimumFractionDigits(if (pad) places else 0)
      formatter.setMaximumFractionDigits(places)
      negParenTransform(useColor,doNegParens,formatter)
    })
    //TODO neg parens
    def devolve(ops: NelOp) = {
      val op = ops.head
      def npct(oh: PrimExpr, round: Boolean = false) = {
        val opx100 = Mul(op, OpLiteral(oh))
        Concat(List(if (round) roundOp(places, opx100) else opx100,
                    OpLiteral(StringExpr(false, "%"))))
      }
      op.guessType.toOption collect {
        case DoubleT(_) => npct(DoubleExpr(false, 100), true)
        case LongT(_) => npct(LongExpr(false, 100))
        case IntT(_) => npct(IntExpr(false, 100))
        case ShortT(_) => npct(ShortExpr(false, 100))
        case ByteT(_) => npct(ByteExpr(false, 100))
      } getOrElse op
    }
  }

  /** Format as currency, where 1.15 displays as "$1.15" if `symbol` is
    * `"USD"`.
    */
  case class Currency(useColor: Boolean, doNegParens: Boolean, symbol: String) extends Format {
    val basicEval = CurrencyObj.fmt(useColor, doNegParens, symbol, java.util.Locale.US)
    //TODO neg parens
    def devolve(ops: NelOp) = {
      val (sym, places) = CurrencyObj.settings(symbol, java.util.Locale.US)
      val op = ops.head
      Concat(List(OpLiteral(StringExpr(false, sym)),
                  op.guessType.toOption collect {
                    case DoubleT(_) => roundOp(places, op)
                  } getOrElse op))
    }
  }

  object CurrencyObj { //extends (String abs_=> Currency) {
    private[this]
    def fromIAE[A](a: => A): IllegalArgumentException \/ A =
      try \/-(a) catch {case e: IllegalArgumentException => -\/(e)}

    private[this]
    def jcurrency(symbol: String, locale: Locale): Option[JCurrency] =
      fromIAE(JCurrency getInstance symbol)
        .orElse(fromIAE(JCurrency getInstance locale))
        .orElse(fromIAE(JCurrency getInstance Locale.US))
        .orElse(fromIAE(JCurrency getInstance Locale.getDefault))
        .toOption

    private[writers]
    def settings(symbol: String, locale: Locale): (String, Int) =
      jcurrency(symbol, locale)
        .map(cur => (cur getSymbol locale, 0 max cur.getDefaultFractionDigits))
        .getOrElse((symbol, 2))

    private[writers]
    def fmt(useColor : Boolean, doNegParens: Boolean, symbol: String, locale: Locale): NonEmptyList[PrimExpr] => PrimExpr = {
      val (sym, places) = settings(symbol, locale)
      numberFormatEval{tlv{
        val formatter = ThreadUnsafeNumberFormat getInstance locale
        formatter.setMinimumFractionDigits(places)
        formatter.setMaximumFractionDigits(places)
        negParenTransform(useColor, doNegParens,formatter)
      }} andThen (_ match {case StringExpr(n, s) => StringExpr(n, sym |+| s)
                           case pe => pe})
    }
  }

  /** Given a base format, return a format on pairs that throws out the
    * second projection. */
  case class Pr1( fst: Format ) extends Format {
    val basicEval = recursiveEval(_.basicEval)
    def devolve(ops: NelOp) = (ops.head, ops.tail) match {
      case (h, t :: u) => fst.devolve(NonEmptyList(h, u :_*))
      case (h, _) => fst.devolve(NonEmptyList(h))
    }

    override def recursiveEval(rec: Format => NelPe => PrimExpr) = (pes: NelPe) => (pes.head, pes.tail) match {
      case (h, it :: u) => rec(fst)(NonEmptyList(h, u:_*))
      case (h, _) => rec(fst)(NonEmptyList(h))
    }
  }
  
  /** Meant for two-field displays: format as one field, a date
    * range. */
  case object DateRange extends Format {
    val basicEval = (pes: NelPe) => (pes.head, pes.tail) match {
      case (DateExpr(n1, startRange), DateExpr(n2, endRange) :: _) =>
        StringExpr(n1 || n2, formatDate(startRange) |+| "–" |+| formatDate(endRange))
      case (pe, _) => pe
    }

    def devolve(ops: NelOp) = ops match {
      case NonEmptyList(s, e, _*) =>
        (s.guessType.toOption, e.guessType.toOption) match {
          case (Some(DateT(_)), Some(DateT(_))) =>
            Concat(List(s, OpLiteral(StringExpr(false, "–")), e))
          case _ => s
        }
      case NonEmptyList(o, _*) => o
    }
  }

  /** Round to `places` after the decimal point. */
  case class Round(useColor: Boolean, doNegParens: Boolean, places: Int) extends Format {
    assert(places >= 0)
    val basicEval = numberFormatEval(tlv {
      val formatter = ThreadUnsafeNumberFormat.getNumberInstance
      formatter setMinimumFractionDigits places
      formatter setMaximumFractionDigits places
      negParenTransform(useColor, doNegParens, formatter)
      })

    def devolve(ops: NelOp) = {
      val op = ops.head
      op.guessType.toOption collect {
        case DoubleT(_) => if(doNegParens) negParenOp(roundOp(places, op)) else roundOp(places,op)
      } getOrElse op
    }
  }

  /** As with `Round`, but show integral results with no decimal
    * places.
    */
  case class IntegralRound(useColor: Boolean, doNegParens:Boolean, places: Int) extends Format {
    assert(places >= 0)
    private val rbe = numberFormatEval(tlv {
      val formatter = ThreadUnsafeNumberFormat.getNumberInstance
      formatter setMaximumFractionDigits places
      negParenTransform(useColor, doNegParens, formatter)
      })
    private val f: NelPe => NelPe = (pes: NelPe) => pes.map( _ match {
      case d@DoubleExpr(n, v) =>
        if(v == math.floor(v) && ! java.lang.Double.isInfinite(v)) IntExpr(n, v.toInt) else d
      case pe => pe
    })
    val basicEval = rbe compose f

    def devolve(ops: NelOp) = {
      val op = ops.head
      op.guessType.toOption collect {
        case DoubleT(_) => if(doNegParens) negParenOp(roundOp(places, op)) else roundOp(places,op)
      } getOrElse op
    }
  }

  case class Truncate(places: Int) extends Format {
    assert(places >= 0)
    val basicEval = (pes: NelPe) => pes.head match {
      case StringExpr(n, v) => StringExpr(n, v.take(places) )
      case pe => pe
    }

    def devolve(ops: NelOp) = ops.head
  }

  case class Conditional(cond: Condition, apply: Format, notApply: Format) extends Format {
    val basicEval = recursiveEval(_.basicEval)

    def devolve(ops: NelOp) = ops.head

    override def recursiveEval(rec: Format => NelPe => PrimExpr) = (pes: NelPe) =>
      if(cond(pes.head))
        rec(apply)(pes)
      else rec(notApply)(pes)
  }

  case class ColorFormat(backColor: Color, frontColor: Color, base: Format) extends Format{
    val basicEval = recursiveEval(_.basicEval)

    def devolve(ops: NelOp) = ops.head

    override def recursiveEval(rec: Format => NelPe => PrimExpr) = (pes: NelPe) =>
      StringExpr(false,"<COLOR_FORMAT>" + rec(base)(pes).extractNullableString("-") + "</COLOR_FORMAT>")
  }

  implicit val formatInstance: Equal[Format] = Equal.equalA
}
