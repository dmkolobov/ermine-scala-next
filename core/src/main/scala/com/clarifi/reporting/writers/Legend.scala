package com.clarifi.reporting
package writers

import writers.{Markdown => MarkdownParser}

import collection.immutable.IndexedSeq

import scalaz.{Applicative, Equal, Functor, Monad, Monoid,
               NonEmptyList, Order, Ordering, Semigroup, State}
import scalaz.Lens.mapVLens
import scalaz.Scalaz.{mzero => _, _}
import scalaz.WriterT.writerMonad
import scalaz.std.indexedSeq._
import scalaz.std.option._
import scalaz.std.tuple._
import scalaz.syntax.monoid._
import scalaz.syntax.std.vector._

/** Label and order information for a particular ρ type.
  *
  * @param inOrder
  *
  * @tparam Lbl The functor's abstract value.  Certain operations,
  *     like `deriveSort`, expect this to obey equality and hashing
  *     laws.  `orderedPresentations` may contain duplicates, but this
  *     might not mean something you like.
  */
case class Legend[Lbl](inOrder: Seq[(Presentation, SortStrategy, Lbl)], undisplayed: Seq[(ColumnName, PrimT, SortOrder)])
     extends TraversableColumns[Legend[Lbl]] {
  assert(inOrder forall {case (pr, sortBy, _) =>
           pr.columnReferences === sortBy.columnReferences},
         "sortBy must completely describe displayData")

  def append(right: Legend[Lbl]) = Legend(inOrder ++ right.inOrder, undisplayed ++ right.undisplayed)

  def labels: Seq[Lbl] = inOrder.view.map(_._3)
  def formats = inOrder.map( _._1.format)

  def orderedPresentations: Seq[(Presentation, Lbl)] =
    inOrder.view map {case (p, _, l) => (p, l)}

  /** In-order traversal of columns described by this legend. */
  def traverseColumns[F[_]: Applicative](f: ColumnName => F[ColumnName]): F[Legend[Lbl]] = {
    val inOrderF = inOrder.toList.traverse {
      case (prs, sortBy, lbl) => ((prs traverseColumns f) |@| (sortBy traverseColumns f))((_, _, lbl))
    }
    val undisplayedF = undisplayed.toList.traverse {
      case (col, pt, so) => f(col) map (c => (c, pt, so))
    }
    ^(inOrderF, undisplayedF)(Legend.apply)
  }

  def typedColumnFoldMap[Z: Monoid](f: (ColumnName, PrimT) => Z): Z = {
    val inOrderZ = inOrder.toIndexedSeq foldMap {case (pr, ss, _) =>
        (pr typedColumnFoldMap f) |+| (ss typedColumnFoldMap f)}
    val undisplayedZ = undisplayed.toIndexedSeq foldMap {case (col, pt, _) => f(col, pt)}
    inOrderZ |+| undisplayedZ
  }

  /** Lift `f` and apply to the receiver. */
  def map[B](f: Lbl => B): Legend[B] = Legend(inOrder map (_ map f), undisplayed)

  /** Legend is traversable. */
  def traverse[F[_]: Applicative, B](f: Lbl => F[B]): F[Legend[B]] =
    inOrder.toIndexedSeq traverse (_ traverse f) map (s => Legend(s, undisplayed))

  private[this] def sortRules: Map[Lbl, List[SortStrategy]] =
    (inOrder groupBy (_._3) mapValues (_ map (_._2) toList))

  /** Find the sort to be applied to the underlying relations I
    * describe, according to a sort specified in terms of labels.
    *
    * @see [[com.clarifi.reporting.writers.TestLegend]]
    */
  def deriveSort(viewSorts: TraversableOnce[(Lbl, SortOrder)]
               ): IndexedSeq[(ColumnName, SortOrder)] = {
    import SortDirection._

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
    Vector(viewSort:_*).filterM[({type F[X]=State[Map[Lbl, Int], X]})#F]{case (lbl, _) =>
      val clbl = mapVLens[Lbl, Int](lbl).xmapB(identity)((_:Option[Int]) filter (0<))
      clbl flatMap (_ >| ((clbl %= (_ map (_-1))) >| true) | state(false))
    } eval sortRules.mapValues(_.size)

  /** Answer a default sort of all columns, left to right. */
  def leftToRightSort: IndexedSeq[(Lbl, SortOrder)] =
    labels.map(_ -> SortOrder.Asc).toIndexedSeq

  /** The built-in evaluation strategy for legends.  Legends consist
    * entirely of data, so this strategy may be displaced by
    * alternatives, such as a writer-specific presentation
    * interpreter.
    */
  lazy val basicEval: Record => IndexedSeq[PrimExpr] = {
    val kvm = (orderedPresentations map {_._1.basicEval} toIndexedSeq)
    (t: Record) => kvm map {_(t)}
  }
}

object Legend {
  /** Add a legend to a presentation. */
  def overPresentation[Lbl](p: Presentation, label: Lbl) =
    Legend(IndexedSeq((p, SortStrategy allForward p.columnReferencesList.distinct,
                       label)), IndexedSeq.empty)

  /** Add a legend to a presentation, with ordering.  Convenient for
    * Ermine. */
  def overPresentation[Lbl](p: Presentation, sort: List[(ColumnName, SortDirection)],
                            label: Lbl) =
    Legend(IndexedSeq((p, SortStrategy(sort), label)), IndexedSeq.empty)

  def hiding(op: Op, ss: SortStrategy, sp: Option[(SortOrder, Int)]) = {
    val typedColRefsMap = op.typedColumnReferencesList.toMap
    Legend(
      IndexedSeq.empty,
      sp.map(soi => ss(soi._1)).getOrElse(Nil) collect {
        case (c, so) if typedColRefsMap.contains(c) =>
          (c, typedColRefsMap(c), so)
      }
    )
  }

  /** The empty legend. */
  def empty[Lbl] = Legend[Lbl](IndexedSeq.empty, IndexedSeq.empty)

  /** Legend is a functor. */
  implicit val LegendFunctor: Functor[Legend] = new Functor[Legend] {
    def map[A, B](r: Legend[A])(f: A => B) = r map f
  }

  /** Legend is a monoid. */
  implicit def LegendMonoid[Lbl]: Monoid[Legend[Lbl]] = new Monoid[Legend[Lbl]] {
    def zero = Legend.empty
    def append(a: Legend[Lbl], b: => Legend[Lbl]): Legend[Lbl] = a append b
  }

  /** Legends can be equal. */
  implicit def LegendEqual[Lbl: Equal]: Equal[Legend[Lbl]] = new Equal[Legend[Lbl]] {
    def equal(l: Legend[Lbl], r: Legend[Lbl]) =
      l.inOrder.toIndexedSeq === r.inOrder.toIndexedSeq
    override def equalIsNatural = false
  }

  /** The legend that only picks columns in a particular order. */
  def select(cols: Seq[ColumnName], h: ColumnName => PrimT): Legend[ColumnName] =
    Legend(cols map (c => (Presentation.unit(NonEmptyList(c -> h(c))),
                           SortStrategy allForward IndexedSeq(c),
                           c)), IndexedSeq.empty)
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

  implicit def sortDirectionInstance: Order[SortDirection] = new Order[SortDirection] {
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

/** Fixed, field-independent description of how to format a field. */
sealed trait Format {
  /** Homomorphism of evaluation results to PrimExprs displayed as
    * with `Default`, for this Format. */
  def basicEval: NonEmptyList[PrimExpr] => PrimExpr
}

object Format {
  import ReportingUtils.{threadLocal => tlv}
  import PrimExprs.formatDate
  import java.text.{
    MessageFormat => ThreadUnsafeMessageFormat,
    NumberFormat => ThreadUnsafeNumberFormat
  }

  private type NelPe = NonEmptyList[PrimExpr]

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

  /** Use whatever the default formatting for the Op type seems to
    * be. */
  case object Default extends Format {
    val basicEval = (_: NelPe).head
  }

  /** like Default, but should interpret + apply markdown formatting
    * to strings. Markdown is already taken by an object associated with the markdown parser,
    * so call it MarkdownFmt to disambiguate */
  case class Markdown( wrapped: Format ) extends Format {
    val basicEval = (pes: NelPe) => wrapped match {
      case Truncate(places) => pes.head match {
                                 case StringExpr(n, v) => { assert(places >= 0)
                                                            StringExpr(n,MarkdownParser.truncateMarkdown(v,places))
                                                          }
                                 case pe => pe
                               }
     case _ => wrapped.basicEval(pes)
     }
  }

  /** Format as a percentage, where numeric 1 displays as "100%". */
  case class Percentage(places: Int, pad: Boolean) extends Format {
    val basicEval = numberFormatEval{tlv{
      val formatter = ThreadUnsafeNumberFormat.getPercentInstance
      formatter.setMinimumFractionDigits(if (pad) places else 0)
      formatter.setMaximumFractionDigits(places)
      formatter
    }}
  }

  /** Format as currency, where 1.15 displays as "$1.15". */
  case class Currency(symbol: String) extends Format {
    val basicEval = numberFormatEval(tlv(ThreadUnsafeNumberFormat getCurrencyInstance
                                         java.util.Locale.US))
  }

  /** Meant for two-field displays: format as one field, a date
    * range. */
  case object DateRange extends Format {
    val basicEval = (pes: NelPe) => (pes.head, pes.tail) match {
      case (DateExpr(n1, startRange), DateExpr(n2, endRange) :: _) =>
        StringExpr(n1 || n2, formatDate(startRange) |+| "–" |+| formatDate(endRange))
      case (pe, _) => pe
    }
  }

  /** Round to `places` after the decimal point. */
  case class Round(places: Int) extends Format {
    assert(places >= 0)
    val basicEval = numberFormatEval(tlv {
      val nf = ThreadUnsafeNumberFormat.getNumberInstance
      nf setMinimumFractionDigits places
      nf setMaximumFractionDigits places
      nf})
  }

  /** As with `Round`, but show integral results with no decimal
    * places.
    */
  case class IntegralRound(places: Int) extends Format {
    assert(places >= 0)
    private val rbe = numberFormatEval(tlv {
      val nf = ThreadUnsafeNumberFormat.getNumberInstance
      nf setMaximumFractionDigits places
      nf})
    private val f: NelPe => NelPe = (pes: NelPe) => pes.map( _ match {
      case d@DoubleExpr(n, v) =>
        if(v == math.floor(v) && ! java.lang.Double.isInfinite(v)) IntExpr(n, v.toInt) else d
      case pe => pe
    })
    val basicEval = rbe compose f
  }

  case class Truncate(places: Int) extends Format {
    assert(places >= 0)
    val basicEval = (pes: NelPe) => pes.head match {
      case StringExpr(n, v) => StringExpr(n, v.take(places) )
      case pe => pe
    }
  }


  /** Format forms a semigroup with respect to domain totality,
    * followed by maximal codomain information.
    *
    * @note fmt |+| fmt = fmt
    */
  implicit val formatInstance: Semigroup[Format] with Equal[Format] =
    new Semigroup[Format] with Equal[Format] {
      def append(l: Format, r: => Format): Format = (l, r) match {
        case (Percentage(n, p1), Percentage(m, p2)) => Percentage(n max m, p1 || p2)
        case (Markdown(f), Markdown(g))       => if (f.equals(g)) l else Default
        case (Currency(n), Currency(m)) => if (n == m) l else Default
        case (DateRange, DateRange)     => l
        case (Round(n), Round(m))       => Round(n max m)
        case (Round(n), IntegralRound(m)) => Round(n max m)
        case (IntegralRound(n), Round(m)) => Round(n max m)
        case (IntegralRound(n), IntegralRound(m)) => IntegralRound(n max m)
        case (Truncate(n), Truncate(m)) => Truncate(n max m)
        case (_, _)                     => Default
      }

      def equal(l: Format, r: Format) = l == r
      override def equalIsNatural = true
    }
}
