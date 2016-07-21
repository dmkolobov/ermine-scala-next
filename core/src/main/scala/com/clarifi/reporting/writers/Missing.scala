// Missing parts of writer implementations.
package com.clarifi.reporting
package writers

import scalaz.{Bifunctor, NonEmptyList}

import relational.ClosedExt

/** Implementation stubs for incomplete writers. */
object Missing {
  trait TreeMap[F[_], C] { self: Writer[F, C] =>
    final override
    def treeMap(parentCol: String, childCol: String,
                labelCol: Presentation, intensityCol: Presentation, sizeCol: Presentation,
                data: TreeTabular[F,Record]): F[C] = sys.error("todo: tree map")
  }

  trait PCAgnosticTreeMap[F[_], C] { self: Writer[F, C] with WDefault.TreeRelationAgnostic[F, C] =>
    final override
    def treeMap(labelCol: Presentation, intensityCol: Presentation, sizeCol: Presentation,
                data: TreeTabular[F,Record]): F[C] = sys.error("todo: tree map")
  }

  trait ForeignSink[F[_], C] { self: Writer[F, C] =>
    final override
    def foreignSink[A](nm: String, f : (A => F[C]) => F[C]) : F[C] =
      sys.error("todo: implement Writer.foreignSink")
  }

  trait PieBarChart2[F[_], C] { self: Writer[F, C] =>
    final override
    def drilldownPieChart2(pcd: PieChartData, labelColumn: Presentation, dataCol : Presentation, cols: List[(String, String)], roots: ClosedExt, data: TreeTabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]): F[C] = sys.error("todo")

    final override
    def drilldownBarChart2(chart: DrilldownBarAxisChart[(List[(String, String)], ClosedExt), TreeTabular[F,(NonEmptyList[PrimExpr], NonEmptyList[PrimExpr])]]): F[C] = sys.error("todo")
  }

  trait Widget[F[_], C] { self: Writer[F, C] =>
    final override
    def widget[S](state: S, controls: (S, (S => F[C])) => F[C], view: S => F[C]) : F[C] =
      sys.error("todo: implement Writer.widget")
  }
}

/** Degraded behavior for writers. */
object WDefault {
  trait AtomFont[F[_], C] { self: Writer[F, C] =>
    override final
    def atomFont(fonts: List[Font], fontSize: Option[Int], f: Format, p: NonEmptyList[PrimExpr]): C = atom(f, p)
  }

  trait WordWrap[F[_], C] { self: Writer[F, C] =>
    override final
    def wrapAtom(s: List[Magnitude], f: Format, p: NonEmptyList[PrimExpr]): C = atom(f,p)

    override final
    def wrapAtomFont(s: List[Magnitude], fonts: List[Font], fontSize: Option[Int], f: Format, p: NonEmptyList[PrimExpr]): C = atomFont(fonts, fontSize, f, p)
  }

  trait ImageViaMarkdown[F[_], C] { self: Writer[F, C] =>
    override final
    def image(fileName: String, altText: Option[String]): C = {
      // If someone has markdown implemented, they might be able to display the image
      atom(Format.Markdown(Format.Default), NonEmptyList(StringExpr( false , "![" + altText.getOrElse("") + "](" + fileName + ")" )))
    }
  }

  trait GridViaHVFlow[F[_], C] { self: Writer[F, C] =>
    override final
    def grid(data: List[List[C]]): C = {
      // Note: this isn't grid like, but will work "well enough" until a writer implements this
      /* example of non gridlike behaivor (because information isn't shared between the vflows):
       *    1 3 5
       *    1 4 5
       *    1   6
       *    2
       */
      horizontalFlow( data.transpose.map( verticalFlow ))
    }
  }

  /** Writers that don't care how `TreeTabular`s are constructed, i.e.
    * don't look at the parentCol/childCol or cols.
    */
  trait TreeRelationAgnostic[F[_], C] { self: Writer[F, C] =>
    def drilldownTable(labelColumn: String,isDefaultLegend: Boolean, t: TreeTabular[F, Record]): F[C]

    final override
    def drilldownTable(labelColumn: String, parentCol: String, childCol: String,isDefaultLegend: Boolean, t: TreeTabular[F, Record]): F[C] =
      drilldownTable(labelColumn,isDefaultLegend, t)

    final override
    def drilldownTable2(labelColumn: String, cols: List[(String, String)],isDefaultLegend: Boolean, t: TreeTabular[F, Record]): F[C] =
      drilldownTable(labelColumn,isDefaultLegend, t)

    def drilldownPieChart(pcd: PieChartData, labelColumn: Presentation, dataCol : Presentation, data: TreeTabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]): F[C]

    final override
    def drilldownPieChart(pcd: PieChartData, labelColumn: Presentation, dataCol : Presentation, parentCol: String, childCol: String, data: TreeTabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]): F[C] =
      drilldownPieChart(pcd, labelColumn, dataCol, data)

    final override
    def drilldownPieChart2(pcd: PieChartData, labelColumn: Presentation, dataCol : Presentation, cols: List[(String, String)], roots: ClosedExt, data: TreeTabular[F,(NonEmptyList[PrimExpr],NonEmptyList[PrimExpr])]): F[C] =
      drilldownPieChart(pcd, labelColumn, dataCol, data)

    def drilldownBarChart(chart: DrilldownBarAxisChart[Unit, TreeTabular[F,(NonEmptyList[PrimExpr], NonEmptyList[PrimExpr])]]): F[C]

    final override
    def drilldownBarChartPC(chart: DrilldownBarAxisChart[(String, String), TreeTabular[F,(NonEmptyList[PrimExpr], NonEmptyList[PrimExpr])]]): F[C] =
      drilldownBarChart(Bifunctor[DrilldownBarAxisChart].leftFunctor.void(chart))

    final override
    def drilldownBarChart2(chart: DrilldownBarAxisChart[(List[(String, String)], ClosedExt), TreeTabular[F,(NonEmptyList[PrimExpr], NonEmptyList[PrimExpr])]]): F[C] =
      drilldownBarChart(Bifunctor[DrilldownBarAxisChart].leftFunctor.void(chart))

    def treeMap(labelCol: Presentation, intensityCol: Presentation, sizeCol: Presentation,
                data: TreeTabular[F,Record]): F[C]

    final override
    def treeMap(parentCol: String, childCol: String,
                labelCol: Presentation, intensityCol: Presentation, sizeCol: Presentation,
                data: TreeTabular[F,Record]): F[C] =
      treeMap(labelCol, intensityCol, sizeCol, data)
  }

  trait PrefSize[F[_], C] { self: Writer[F, C] =>
    import Magnitude._

    final override
    def prefArea(as: List[Area], target: C): C = target
    final override
    def prefHeight(as: List[Magnitude], target: C): C = target
    final override
    def prefWidth(as: List[Magnitude], target: C): C = target
  }

  trait MaxSize[F[_], C] { self: Writer[F, C] =>
    import Magnitude._

    final override
    def maxArea(as: List[Area], target: C): C = target
    final override
    def maxHeight(as: List[Magnitude], target: C): C = target
    final override
    def maxWidth(as: List[Magnitude], target: C): C = target
  }

  trait CollapsibleViaStyle[F[_], C] { self: Writer[F, C] =>
    final override
    def collapsible(expanded: java.lang.Boolean, title: String, body: C): C =
      style("collapsible",
        verticalFlow(List(
          style("collapsible-title", atom(Format.Default, NonEmptyList(StringExpr(false, title)))),
          style("collapsible-body", body)))
      )
  }

  trait SideTabbedIsTopTabbed[F[_], C] { self: Writer[F, C] =>
    final override
    def sideTabbed(cs: List[(String,C)]): C = tabbed(cs)
  }

  trait TextAreaToTextBox[F[_], C] { self: Writer[F, C] =>
    final override
    def textArea(default: String , f: (String => C, SelectorEvent, ((String => F[C]) => F[C])) => F[C]): F[C] = textBox(default, f)
  }
}
