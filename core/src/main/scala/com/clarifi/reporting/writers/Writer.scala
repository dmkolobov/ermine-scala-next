package com.clarifi.reporting
package writers

import java.awt.Color
import java.util.{Date, UUID}
import collection.immutable.IndexedSeq

import scalaz.{Order, Foldable, Functor, Monad, NonEmptyList, Tree, Tag, Tags}
import scalaz.std.vector._
import scalaz.syntax.bifunctor._
import scalaz.syntax.equal._
import scalaz.syntax.monad._
import scalaz.syntax.foldable._
import scalaz.std.list._
import com.clarifi.machines._

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.relational._
import com.clarifi.reporting.backends.DB
import Writer._
import Magnitude._
import com.clarifi.machines._
import java.awt.Color
import Predicate._

/** Display style for the widget used for selection. */
sealed trait SelectorMode
  case object Dropdown extends SelectorMode
  case object RadioButton extends SelectorMode
  case object CheckBox extends SelectorMode
  case object TextBox extends SelectorMode
  case object TextArea extends SelectorMode
  case object Slider extends SelectorMode
  case class ForeignMode(nm : String) extends SelectorMode


object SelectorModes {
  val dropdown    = Dropdown
  val radioButton = RadioButton
  val checkBox    = CheckBox
  val slider      = Slider
  val textBox     = TextBox
  val textArea    = TextArea
}

//selector events are things that union (aka commutative monoids)
abstract class SelectorEvent{
  def or(that: SelectorEvent): SelectorEvent
}

//Live means "null event"
object SelectorEvents {
  def live = Live
}

case object Live extends SelectorEvent{
  def or(that: SelectorEvent): SelectorEvent = that
}

/** The suspended display of a single unit of record-extracted data.
 *
 * @param format Rules for displaying `primExprs`.
 * @param primExprs Data to be displayed. */
case class Atomic(format: Format, primExprs: NonEmptyList[PrimExpr])
  extends Function0[PrimExpr] {
  /** Use the default display strategy on `primExprs`. */
  def apply() = format basicEval primExprs

  override def toString = "Atomic(%s,%s)" format (format, primExprs)
}
object Atomic extends Function2[Format, NonEmptyList[PrimExpr], Atomic] {
  implicit val atomicOrder: Order[Atomic] = PrimExpr.PrimExprOrder.contramap( a => a.primExprs.head )
}
/** Writer contains the logic needed to convert an abstract description of a report
  * to an `F[C]`, where `C` is called the component type for the `Writer`. The
  * `Writer` has access to a `Scanner` for `F`, which it can use to execute
  * data queries within the monad `F`.
  *
  * Writer functions which may require data loading return `F[C]`, those that don't
  * return just `C`.
  *
  * @note Methods that return `F[''X'']` for some ''X'' are required to
  *  control all side-effects with the `F` monad; they must not happen
  *  during execution of said method.  Methods that return `C` are always
  *  lifted into `F`, so simple avoidance of `val` and `lazy val` in
  *  favor of `def` should be sufficient for side-effect control in
  *  those cases.
  */
abstract class Writer[F[_],C] { self =>
  implicit def B: Scanner[F]
  implicit def F: Monad[F] = B.M

  type Signal[A] = (A => F[C]) => F[C]

  /** The empty component - should be an identity for all types of composition. */
  def empty: C

  /** A text label */
  def atom(f: Format, p: NonEmptyList[PrimExpr]): C

  /** a text label with font information */
  def atomFont(fonts: List[Font], fontSize: Option[Int], f: Format, p: NonEmptyList[PrimExpr]): C

  /** a word-wrapped text label */
  def wrapAtom(s: List[Magnitude], f: Format, p: NonEmptyList[PrimExpr]): C
  /** a word-wrapped text label with font info*/
  def wrapAtomFont(s: List[Magnitude], fonts: List[Font], fontSize: Option[Int], f: Format, p: NonEmptyList[PrimExpr]): C

  /*  Hack Alert: we need the ability to take a date formatter
      Currently, the ExcelWriter and JFXWriter are parameterized on a formatter
      We'd like the ability to expose this in Ermine.
      So, this function, while ugly and seemingly misplaced, was born.
   */
  def dateToString(d: Date): String = PrimExprs.formatDate(d)

  def image(fileName: String, altText: Option[String]): C // = {
    // If someone has markdown implemented, they might be able to display the image
    //atom(Format.Markdown(Format.Default), NonEmptyList(StringExpr( false , "![" + altText.getOrElse("") + "](" + fileName + ")" )))
  //}

  /** Assign a style to the target that may be used to influence the writer.
    * By default styles are ignored.
    */
  def style(h: String, target: C): C = target

  /** The target should recognize that it has a preferred size */
  // def prefSize(w: Option[Int], h: Option[Int], target: C): C = target
  def prefArea(as: List[Area], target: C): C
  def prefHeight(as: List[Magnitude], target: C): C
  def prefWidth(as: List[Magnitude], target: C): C

  def maxArea(as: List[Area], target: C): C
  def maxHeight(as: List[Magnitude], target: C): C
  def maxWidth(as: List[Magnitude], target: C): C

  // ignore these if we can't implement them
  def backgroundColor(c: Color, target: C): C = target
  def foregroundColor(c: Color, target: C): C = target

  def borderSize(opts: BorderOptions[(LineStyle, LineThickness)], target: C) = target
  def borderColor(c: BorderOptions[Color], target: C) = target
  // Similar to border, but the padding should have the same style as the adjacent areas
  def pad( opts: BorderOptions[List[Magnitude]], target: C ) = target

  /** The target should be wrapped in a C that supports scrolling.
    * By default this has no effect, simply returning the target itself.
    */
  def scrolling(target: C): C = target

  /** A grid layout of the reports where each element of the outer list is a row
    * and that rows elements become columns */
  def grid(data: List[List[C]]): C

  /** A table-like laybout of the reports with table header and table body.
    * CSSClass can be applied on each row and column  */
  private def styleWithCSS(css: Option[String], target: C) : C = css.fold(target)(s => style(s, target))

  def styleBox(header: List[(Option[String], List[(Option[String], C)])], body: List[(Option[String], List[(Option[String], (C, C))])]) : C = {
    var h : List[List[C]] = header.map(_._2.map(x => styleWithCSS(x._1, x._2)))
    var b : List[List[C]] = body.map(_._2.map(x => List (styleWithCSS(x._1, x._2._1), styleWithCSS(x._1, x._2._2))).flatten) // ignore the click on event 
    // SOMETHING TO DO 
    grid (h ++ b) 
  }

  /** A table described by a `Column.Table` structure.  The default
    * exploits equivalence with `table` and `drilldownTable`; you are
    * free to reinterpret it.
    */
  def columnTable(displayTransposed: Boolean, table: Column.Table[Atomic, ClosedExt]): F[C] = {
    val tablestr = ((_:Atomic)() extractNullableString "") <-: table
    val (ext, lgstr) = KeyValueTabular dynamicSchema tablestr
    val initSort = tablestr.initialSort.toList

    (table.rootNodes, table.drilldown) match {
      case (Some(roots), Some(cols)) =>
            // XXX SMRC We pretend we know what the labelColumn is here.
            // Specify it with the Legend if you want it to be right.
            drilldownTableDMTL2(Some(lgstr), lgstr.columnReferencesList.head, cols.map(_._1),
                               initSort, ext, roots)
      case (None, Some(List(((pid, cid), _)))) =>
            // XXX SMRC We pretend we know what the labelColumn is here.
            // Specify it with the Legend if you want it to be right.
            drilldownTableDMTL(Some(lgstr), lgstr.columnReferencesList.head, pid, cid,
                               initSort, ext)
      case _ => tableDMTL(Some(lgstr), initSort, displayTransposed, ext)
    }
  }

  /** A table of data - `t` may contain a large number of rows and implementations are
    * free to load data from it lazily. */
  def table(t: Tabular[F, Record]): F[C]

  // We generally want to reorder the table so the label column is first, if we have a default legend; this is the most sensible general behaivor
  // We also don't want to rearange a user-supplied legend.
  def drilldownTable(labelColumn: String, parentCol: String, childCol: String, isDefaultLegend: Boolean, t: TreeTabular[F, Record]): F[C]

  def drilldownTable2(labelColumn: String, cols: List[(String, String)], isDefaultLegend: Boolean, t: TreeTabular[F, Record]): F[C] =
    drilldownTable(labelColumn, cols.head._1, cols.head._2, isDefaultLegend, t) // correct as long as the writer ignores parent and child cols, which all do.


  /** @see [[com.clarifi.reporting.writers.AxisChart]] */
  def axisChart(chart: AxisChart[Tabular[F, Record]]): F[C]


  def treeMap(parentCol: String, childCol: String,
              labelCol: Presentation, intensityCol: Presentation, sizeCol: Presentation,
              data: TreeTabular[F,Record]): F[C]

  /** @note Invariant: _2.head of data elements is PrimitiveNum. */
  def pieChart(pcd: PieChartData, labelcol: Presentation, datacol: Presentation, data: Tabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]): F[C]

  /** @note Invariant: _2.head of data elements is PrimitiveNum.
    * @param data Tabular of (label, value) pairs. */
  def drilldownPieChart(pcd: PieChartData, labelColumn: Presentation, dataCol : Presentation, parentCol: String, childCol: String, data: TreeTabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]): F[C]

  /** Create a drilldown bar chart. */
  def drilldownBarChartPC(chart: DrilldownBarAxisChart[(String, String), TreeTabular[F,(NonEmptyList[PrimExpr], NonEmptyList[PrimExpr])]]): F[C]

  /** @note Invariant: _2.head of data elements is PrimitiveNum.
    * @param data Tabular of (label, value) pairs. */
  def drilldownPieChart2(pcd: PieChartData, labelColumn: Presentation, dataCol : Presentation, cols: List[(String, String)], roots: ClosedExt, data: TreeTabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]): F[C]

  /** Create a drilldown bar chart. */
  def drilldownBarChart2(chart: DrilldownBarAxisChart[(List[(String, String)], ClosedExt), TreeTabular[F,(NonEmptyList[PrimExpr], NonEmptyList[PrimExpr])]]): F[C]
  /* This should render something like: https://51help.clarifi.com/Risk_attribution_snapshot */
  def tree(legend: C, t: Tree[C]): C

  /** @see Layout.Report.hspan */
  def horizontalSpan(cs: List[(List[Magnitude],C)]): C

  /** @see Layout.Report.vspan */
  def verticalSpan(cs: List[(List[Magnitude],C)]): C

  /** @see Layout.Report.hflow */
  def horizontalFlow(cs: List[C]): C

  /** @see Layout.Report.vflow */
  def verticalFlow(cs: List[C]): C

  def centered(c: C): C = border(Some(c), None, None, None, None)

  def border(center: Option[C], north: Option[C], south: Option[C], east: Option[C], west: Option[C]): C

  /* djd: TODO: It might be better if this were
   * List[(String,F[C])] => F[C], for the purpose of delaying things in
   * JavaFX, for instance. But that is a somewhat invasive change.
   */
  def tabbed(cs: List[(String,C)]): C

  def sideTabbed(cs: List[(String,C)]): C

  def collapsible(expanded: java.lang.Boolean, title: String, body: C): C

  def scanRelation(r: ClosedExt, f: List[Record] => F[C], order: List[(String, SortOrder)] = List()): F[C] =
    B.scanExt(r.out, Process.wrapping[Record], order).flatMap(i => f(i.toList))

  def run(c: C): Unit

  // DMTL hooks
  final def scanRelationDMTL(order: List[(String, SortOrder)], r: ClosedExt, f: List[Map[String,Runtime]] => F[C]): F[C] =
    scanRelation(r.out, (ts: List[Record]) => f(ts.map(_.mapValues(Runtime fromPrimExpr _))), order)

  /**
   * TODO: review this comment - JC 6/12/12
   * Selector is used to generate linked components like dropdown boxes and radio buttons where
   * the content of one component is updated based on the current selection. This function takes
   * a `SelectorMode`, which indicates the display style to be used for the selection component,
   * a `Choice`, which indicates the source for the set of possible options, and a function for
   * generating a component based on the current selection. It returns a pair of components, linked
   * such that when the user changes the selection (the first component returned), the content
   * in the second component is updated based on the given update function.
   *
   * Invoking the function `f` with an argument of `None` can be used to generate the intial
   * starting view, before the user has made any selection.
   */

  def textBox(default:String, f: (String => C, SelectorEvent, Signal[String]) => F[C]) : F[C] =
    selector(TextBox,(NonEmptyList(StringExpr(false, default)),default),Format.Default,List(),f)

  def textArea(default:String, f: (String => C, SelectorEvent, Signal[String]) => F[C]) : F[C] =
    selector(TextArea,(NonEmptyList(StringExpr(false, default)),default),Format.Default,List(),f)

  def selector[A](mode: SelectorMode, default: (NonEmptyList[PrimExpr],A), fmt: Format, values: List[(NonEmptyList[PrimExpr],A)],
                   f: (A => C, SelectorEvent, Signal[A]) => F[C]
                  ) : F[C]
  // Given a `SelectorEvent` and a report, update the report whenever the event fires.
  def onEvent(evt: SelectorEvent, inner: F[C]) : F[C] = inner

  def button(name: NonEmptyList[PrimExpr], fmt: Format, f: (C, SelectorEvent) => F[C]) : F[C]

  def widget[S](state: S, controls: (S, (S => F[C])) => F[C], view: S => F[C]) : F[C]

  def foreignSelector[A](nm: String, default: A, f : A => F[C]) : F[C] =
                              // todo: do we want to take in a Nel[PrimExpr] and format?
    selector(ForeignMode(nm),(NonEmptyList(StringExpr(false, default.toString)),default),Format.Default,List(),
             {
               case (_,_,k) => k(f)
             } : (A => C, SelectorEvent, Signal[A]) => F[C])

  def foreignSink[A](nm: String, f : (A => F[C]) => F[C]) : F[C]

  final def atomDMTL(fmt: Format, ps: AnyRef): C = atom(fmt, toPrimExprNel(ps))
  final def atomFontDMTL(fonts: List[Font], fontSize: Option[Int], f: Format, ps: AnyRef): C = atomFont(fonts, fontSize, f, toPrimExprNel(ps))
  final def atomWrappedDMTL(s:List[Magnitude], fmt: Format, ps: AnyRef): C = wrapAtom(s,fmt, toPrimExprNel(ps))
  final def atomWrappedFontDMTL(s:List[Magnitude], fonts: List[Font], fontSize: Option[Int], f: Format, ps: AnyRef): C = wrapAtomFont(s,fonts, fontSize, f, toPrimExprNel(ps))

  final def tableDMTL(legend: Option[Legend.U[String]], order: List[(String, SortOrder)], doTranspose: java.lang.Boolean,
                      r: ClosedExt): F[C] = {
    val tabular = Tabular.relationRec(r)
    val inp = legend.map(lg => tabular.label(lg)).getOrElse(tabular).orderBy(order.toIndexedSeq)
    if (doTranspose) { table(inp.transpose) } else { table(inp) }
  }

  final def axisChartDMTL(chart: AxisChart[ClosedExt]): F[C] =
    axisChart(chart map (Tabular.relationRec(_)))

  final def pieChartDMTL(pcd: PieChartData, labelColumn: Presentation, dataColumn: Presentation,
                         r: ClosedExt): F[C] =
    pieChart(pcd, labelColumn, dataColumn, Tabular.relationRec(r).map(tup =>
      (labelColumn extract tup, dataColumn extract tup)))

  /** A hook that allows postponement of some of the below *DMTL functions
   *  for the purpose of avoiding early queries in tabbed reports and such.
   */
  def postpone(w: F[C]): F[C] = w

  final def treeMapDMTL(parentCol: String, childCol: String,
                        labelCol: Presentation, intensityCol: Presentation, sizeCol: Presentation,
                        fact: ClosedExt): F[C] =
    treeTabular(parentCol, childCol, fact, rootParentId = 1) flatMap (ttab =>
      treeMap(parentCol, childCol, labelCol, intensityCol, sizeCol, ttab))

  final def drilldownPieChartDMTL(pcd: PieChartData, labelColumn: Presentation, dataColumn: Presentation,
                                  parentIdColumn: String, childColumn: String, fact: ClosedExt): F[C] =
    postpone(
      treeTabular(parentIdColumn, childColumn, fact, rootParentId = 1) flatMap (ttab =>
        drilldownPieChart(pcd, labelColumn, dataColumn, parentIdColumn, childColumn,
                          ttab.map { tab =>
                            (labelColumn extract tab, dataColumn extract tab) }))
    )

  final def drilldownBarChartDMTL(
    chart: DrilldownBarAxisChart[(String, String), ClosedExt]): F[C] = {
    val DrilldownBarAxisChart(_, categoryPres, dataPres, query, (parentCol, childCol), _) = chart
    postpone(
      treeTabular(parentCol, childCol, query, rootParentId = 1) flatMap (ttab =>
      drilldownBarChartPC(chart.flattenFormat rightMap
                          (_ => ttab map { tab =>
                             (categoryPres extract tab, dataPres extract tab)})))
    )
  }

  final def drilldownTableDMTL(legend: Option[Legend.U[String]]
    , labelColumn: String
    , parentIdColumn: String
    , childColumn: String
    , order: List[(String, SortOrder)]
    , fact: ClosedExt): F[C] =
    postpone(
      treeTabular(parentIdColumn, childColumn, fact, rootParentId = 0) flatMap {tab =>
        drilldownTable(labelColumn, parentIdColumn, childColumn, legend.isEmpty,
                       legend.map(lg => tab.label(lg)).getOrElse(tab)
                         .orderBy(order.toIndexedSeq))
      }
    )

  final def drilldownPieChartDMTL2(pcd: PieChartData, labelColumn: Presentation, dataColumn: Presentation,
                                   cols: List[(String, String)], fact: ClosedExt, roots: ClosedExt): F[C] =
    postpone(
      treeTabular2(cols, fact, roots) flatMap (ttab =>
      drilldownPieChart2(pcd, labelColumn, dataColumn, cols, roots,
                         ttab.map { tab =>
                           (labelColumn extract tab, dataColumn extract tab) }))
    )

  final def drilldownBarChartDMTL2(
    chart: DrilldownBarAxisChart[(List[(String, String)], ClosedExt), ClosedExt]): F[C] = {
    val DrilldownBarAxisChart(_, categoryPres, dataPres, query, (cols, roots), _) = chart
    // TODO ask estern whether the 3rd arg to treeTabular2 makes sense -SMRC
    postpone(
      treeTabular2(cols, query, roots) flatMap (ttab =>
      drilldownBarChart2(chart.flattenFormat rightMap
                           (_ => ttab map { tab =>
                              (categoryPres extract tab, dataPres extract tab)})))
    )
  }

  final def drilldownTableDMTL2(legend: Option[Legend.U[String]], labelColumn: String, cols: List[(String, String)], order: List[(String, SortOrder)], fact: ClosedExt, roots: ClosedExt): F[C] =
    postpone(
      treeTabular2(cols, fact, roots) flatMap {tab =>
        drilldownTable2(labelColumn, cols, legend.isEmpty,
                       legend.map(lg => tab.label(lg)).getOrElse(tab)
                         .orderBy(order.toIndexedSeq))
      }
    )

  /** Alias for `columnTable`. */
  final def columnTableDMTL(table: Column.Table[Atomic, ClosedExt]): F[C] =
    columnTable(false,table)

  final def columnTableTransposedDMTL(table: Column.Table[Atomic, ClosedExt]): F[C] =
    columnTable(true,table)

  // returns a tree tabular of (dimension, fact table row) pairs
  private[this] def treeTabular(parentIdColumn: String,
                                nodeIdColumn: String,
                                fact: ClosedExt,
                                rootParentId: Int = 0): F[TreeTabular[F, Record]] = {
    fact match {
      case Closed(ExtRel(r, _), h) => relTreeTabular(parentIdColumn, nodeIdColumn, fact, rootParentId).pure[F]
      case _ => memTreeTabular(parentIdColumn, nodeIdColumn, fact, rootParentId)
    }
  }

  // builds a tree tabular by scanning the entire relation up front and working on
  // a vector of the results. Possibly quite memory hungry, but can save a lot of
  // repeated work.
  private[this] def memTreeTabular(parentIdColumn: String,
                                   nodeIdColumn: String,
                                   fact: ClosedExt,
                                   rootParentId: Int): F[TreeTabular[F, Record]] = {
    val Closed(e, h) = fact
    val ntype = h.getOrElse(nodeIdColumn,
      sys.error("header " + fact.header + " missing column: " + nodeIdColumn))
    assume(ntype === h(parentIdColumn), "tree relationships must match")
    B scanExt (e, Process.wrapping) map { vfact =>
      val childMap = vfact.groupBy(_(parentIdColumn))
      def go(root: PrimExpr): TreeTabular[F, Record] = new TreeTabular[F, Record] {
        val F = self.F
        def relation = fact
        lazy val children = {
          val query: ClosedExt = mkLiteral(h, childMap.getOrElse(root, Vector()))
          Tabular.relationRec(query).map(tup => (tup, go(tup(nodeIdColumn))))
        }
      }
      go(PrimExpr mkExpr (rootParentId, ntype))
        .label(Tabular displayRecords
               (fact.header -- List(parentIdColumn, nodeIdColumn)))
    }
  }

  private[this] def relTreeTabular(parentIdColumn: String,
                                   nodeIdColumn: String,
                                   fact: ClosedExt,
                                   rootParentId: Int): TreeTabular[F, Record] = {
    import Op._
    val ntype = fact.header.getOrElse(nodeIdColumn,
      sys.error("header " + fact.header + " missing column: " + nodeIdColumn))
    assume(ntype === fact.header(parentIdColumn), "tree relationships must match")
    def go(root: PrimExpr): TreeTabular[F, Record] = new TreeTabular[F, Record] {
      val F = self.F
      def relation = fact
      lazy val children = {
        val query: ClosedExt =
          fact.map(FilterE(_, Predicate.Eq(ColumnValue(parentIdColumn, ntype),
                                           OpLiteral(root))))
        Tabular.relationRec(query).map(tup =>
          (tup, go(tup(nodeIdColumn))))
      }
    }
    // XXX we assume the root of the tree has node id of 1 - should we
    // select rows where parent == child or parent doesn't join anything?
    go(PrimExpr mkExpr (rootParentId, ntype))
      .label(Tabular displayRecords
             (fact.header -- List(parentIdColumn, nodeIdColumn)))
  }

  // returns a tree tabular of (dimension, fact table row) pairs
  private[this] def treeTabular2( cols: List[(String, String)], // parent, node tuples
                                fact: ClosedExt,
                                rootFact: ClosedExt): F[TreeTabular[F, Record]] = {
    import Op._
    val nodes = cols.map( _._2 )
    val parents = cols.map( _._1 )
    val ntypes = nodes.map( nodeIdColumn => fact.header.getOrElse(nodeIdColumn,
      sys.error("header " + fact.header + " missing column: " + nodeIdColumn)))
    assume(ntypes.equals(parents.map(fact.header)), "tree relationships must match")

    // There are two ways to create the drilldown structure.
    // One way is to read everything into memory, and just work on a scala collection
    // the other is to use predicates.
    // Predicates make sense for Rels: we can let the database do a lot of work, and it will cache a lot of stuff
    // working in memory makes sense for Mems, because we can't share information between the calls to run very slightly different mems
    // So, implement both and call the one that makes sense for your type.

    def withPredicate(qfact: ClosedExt) = {
      def go(roots: IndexedSeq[List[PrimExpr]]): TreeTabular[F, Record] = new TreeTabular[F, Record] {
      //def go(roots: ClosedExt]): TreeTabular[F, Record] = new TreeTabular[F, Record] {
        val F = self.F
        def relation = fact
        lazy val children = {
          val predicate =
          roots.map({
            root =>
              root.zip(ntypes).zip(parents).foldMap( {
                case(((curValue, typ), parentColumn)) => Tag.apply[Predicate, Tags.Conjunction](
                                                           Predicate.Eq( ColumnValue(parentColumn, typ),
                                                                         OpLiteral(curValue)))
                })(PredicateAndMonoid)})
                .foldLeft(Atom(false) : Predicate)( Or(_,_) )

          val query: ClosedExt =
            qfact.map(FilterE(_, predicate))
          Tabular.relationRec(query).map(tup => {
            (tup, go( IndexedSeq(nodes.map(tup)) ))})
        }
      }

      val t = Tabular.relationRec(rootFact).takeAll.map( roots =>
        go( roots.map( root => nodes.map(root)) ))
      t
    }

    def inMem(qfact: ClosedExt) = {
      type CM = Map[List[PrimExpr], IndexedSeq[Record]]

      val (ccols, pcols) = cols unzip
      def parentKey(parent: Record) = pcols.map(parent(_))
      def childKey(child: Record) = ccols.map(child(_))

      def go(roots: IndexedSeq[Record], childMap: CM): TreeTabular[F, Record] = new TreeTabular[F, Record] {
        val F = self.F
        def relation = fact

        def toMem(xs: IndexedSeq[Record]): HardMem = xs.headOption match {
          case Some(x) =>
            relational.Literal(x, xs.tail)
          case _ => relational.EmptyRel(qfact.header)
          }
        val rootMem = Closed(ExtMem( toMem( roots )): Ext[Nothing, Nothing], qfact.header )
        lazy val children =
          new StrictTabular[F, (Record, TreeTabular[F, Record])](
              rootMem
            , IndexedSeq()
            , (header, row) => ( row
                               , go(childMap.getOrElse(parentKey(row), Vector()), childMap)
                               )
            , None
                                                                , None
                                                                , false
            )
      }

      Tabular.relationRec(rootFact).takeAll.flatMap( roots => {
        val parentKeys = roots.map(parentKey).toSet.toIndexedSeq

        Tabular.relationRec(qfact).takeAll.map( rel => {
          val parentLookup = rel.groupBy(parentKey(_))
          val rootRecs = parentKeys.flatMap(parentLookup(_))
          val childLookup = rel.groupBy(childKey(_))

          go(rootRecs, childLookup)
        })
      }
      )
    }

    fact match {
      case Closed(ExtRel(_,_), _) => withPredicate(fact)
      case Closed(ExtMem(mem), _) => inMem(fact)
      case Closed(ExtSM(sm), _) => withPredicate(fact)
    }
  }

  def mapW[A,B](f: A => B, fa: F[A]): F[B] = F.map(fa)(f)
  def lift2W[A,B,C](f: (A,B) => C, fa: F[A], fb: F[B]): F[C] = (fa |@| fb)(f)
  def apW[A,B](fa: F[A => B], fb: F[A]): F[B] = (fa |@| fb)((f,x) => f(x))
  def pureW[A](a: A): F[A] = {
    if (F eq null) sys.error("fail")
    else F.pure(a)
  }
  def bindW[A,B](ma: F[A], f: A => F[B]) = ma flatMap f

  //  method "fixW" fixW   : forall f a b .     Writer f a -> (b -> f b) -> f b
  def fixW[B](f: (=> B) => F[B]) : F[B] = sys.error("todo")
}

object Writer {

  /** Implement Writer#atom in terms of a string display. */
  def displayedAtom[Z](atomShown: String => Z)(f: Format, p: NonEmptyList[PrimExpr]): Z =
    atomShown(f.basicEval(p) extractNullableString "")

  /** Coerce Ermine data, and other sorts, to a NEL of PrimExprs.  See
    * Layout.Report.ChoiceTest for sample calls required to
    * succeed. */
  def toPrimExprNel(v: Any): NonEmptyList[PrimExpr] = v match {
    case v: Runtime => v.whnf match {
      case Prim(v) => toPrimExprNel(v)
      case Arr(Array(tupelt, tupelts@_*)) => // Ermine tuple
        NonEmptyList(tupelt, tupelts:_*) flatMap toPrimExprNel
      case Data(Global("Builtin", "Some", _), Array(v)) =>
        toPrimExprNel(v)
      case Data(Global("Builtin", "Null", _), Array(v)) =>
        NonEmptyList(NullExpr(v.extract[PrimT]))
      case Data(Global("Builtin", "True", _), _) =>
        toPrimExprNel(true)
      case Data(Global("Builtin", "False", _), _) =>
        toPrimExprNel(false)
      case Data(gl@Global(_,_,_), _) =>  // field name, I guess?
        NonEmptyList(StringExpr(false, gl.string))
      case x => NonEmptyList(StringExpr(false, x.nf.toString))
    }
    case Some(v)     => toPrimExprNel(v)
    case v: Boolean  => NonEmptyList(BooleanExpr(false, v))
    case v: Byte     => NonEmptyList(ByteExpr(false, v))
    case v: Short    => NonEmptyList(ShortExpr(false, v))
    case v: Int      => NonEmptyList(IntExpr(false, v))
    case v: Long     => NonEmptyList(LongExpr(false, v))
    case v: Double   => NonEmptyList(DoubleExpr(false, v))
    case v: Date     => NonEmptyList(DateExpr(false, v))
    case v: String   => NonEmptyList(StringExpr(false, v))
    case v: UUID     => NonEmptyList(UuidExpr(false, v))
    case null | None => NonEmptyList(NullExpr(PrimT.StringT(0)))
    case v           => NonEmptyList(StringExpr(false, v.toString))
  }

  def fromPrimExprNel(n:NonEmptyList[PrimExpr]): Runtime = n.tail match {
    case Nil => Runtime.fromPrimExpr(n.head)
    case xs => Arr(n.list.view.map(x => Runtime.fromPrimExpr(x)).toArray)
  }

  def mkLiteral(h: Header, v: Vector[Record]): ClosedExt = Closed(ExtMem(v.headOption match {
    case None => relational.EmptyRel(h)
    case Some(head) => Literal(head, v.tail)
  }), h)

  /** Replace `ei` with its literal scan, in Mem. */
  def literally[F[_]](ei: ClosedExt)(implicit B: Scanner[F], F: Functor[F]
                                   ): F[Mem[Nothing, Nothing]] = {
    val Closed(e, h) = ei
    B scanExt (e, Process.wrapping) map { xs => xs.headOption match {
        case None => relational.EmptyRel(h)
        case Some(head) => Literal(head, xs.tail)
      }
    }
  }
}

