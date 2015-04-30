// KeyValueTabular.scala: Tabular with schema computed from the relation.
package com.clarifi.reporting
package writers

import scalaz.Id._
import scalaz.{IterV, Monoid, NonEmptyList, Reducer, State => St, StateT}
import scalaz.std.set._
import scalaz.std.vector._
import scalaz.syntax.apply._
import scalaz.syntax.bifunctor._
import scalaz.syntax.traverse.{ToFunctorOps => _, ToFunctorOpsUnapply => _, _}
import scalaz.syntax.id._
import scalaz.syntax.monoid._
import scalaz.syntax.std.all.ToTuple2Ops

import com.clarifi.reporting.relational._
import ReportingUtils._

/** Relation endomorphisms, with legend reification, that require a
  * scan.  The general operator is `dynamicSchema`; other functions are
  * utilities for conveniently using it with different biases. */
object KeyValueTabular {
  import com.clarifi.reporting.writers.{Column => C}

  /** State across calls to `freshenColumns`. */
  private type Untangling[A] = StateT[Id, (Set[ColumnName], Stream[ColumnName]), A]

  /** Utility used by `freshenColumns`. */
  private type Traversing[A] = StateT[Id, (Stream[ColumnName],
                                           Map[ColumnName, ColumnName]), A]

  /** Replace column references in `tc` with new references.  Answer
    * the old→new name map and replaced `tc`. */
  private def freshenColumns[TC <: TraversableColumns[TC]](tc: TC):
  Untangling[(Map[ColumnName, ColumnName], TC)] = for {
    start <- St.get[(Set[ColumnName], Stream[ColumnName])]
    (disallowed, src) = start
    ((newsrc, repls), newtc) = tc.traverseColumns[Traversing]{cn =>
      St{case s@(cns, news) =>
           (news get cn map (s ->)
            getOrElse {val safecns = cns dropWhile disallowed
                       ((safecns.tail, news + (cn -> safecns.head)), safecns.head)})
      }} run ((src, Map.empty))
    _ <- St put ((disallowed ++ repls.values, newsrc))
  } yield (repls, newtc)

  /** One step of a fold to produce join-compatible singles of
    * exts. */
  private def freshenSingle[Lbl](s: C.Single[Lbl, ClosedExt]
                               ): Untangling[C.Single[Lbl, Ext[Nothing, Nothing]]] =
    freshenColumns(s) map {case (renames, s) =>
      s :-> {case Closed(e, typ) =>
        (e /: renames){(e, oton) =>
          // By definition, the `n' columns are absent from e's
          // schema, so an iterative renaming is safe.
          RenameE(e, Attribute(oton._1, typ(oton._1)), oton._2)
        }
      }
    }

  /** Make a surrogate column name. */
  private def surrogateColName(num: Int): ColumnName = "surrds" + num

  private def fromJust[A]: Option[A] PartialFunction A = {case Some(a) => a}

  /** Apply Mem operations matching the join types throughout `t`, if
    * non-empty.
    */
  private def joinTree[R, M](t: C.Join[_, Mem[R, M]]): Option[Mem[R, M]] =
    t match {
      case C.Joinee(a) => Some(a)
      case C.InnerJoin(a) =>
        binaryReduce(a.view map joinTree collect fromJust)(HashInnerJoin.apply)
      case C.OuterJoin(a) =>
        binaryReduce(a.view map joinTree collect fromJust)(MergeOuterJoin.apply)
      case C.JoinHeading(_, a) => joinTree(a)
    }

  private def joinLegend[G, L, A](join: C.Join[G, C.Single[L, A]]): Legend[G, L] =
    join.foldGroups(_.singletonLegend[G])((grp, under) => under columnGroup grp)

  /** Represent `e` as a Mem, unconditionally. */
  private def mem[M, R](e: Ext[M, R]): Mem[R, M] = e match {
    case ExtMem(m) => m
    case e => EmbedMem(e)
  }

  /** Extract a relation to scan all of `cjoin`, and a legend to
    * match.
    */
  private def foldJoin[G, Lbl](cjoin: C.Join[G, C.Single[Lbl, ClosedExt]]
                              ): (Option[ClosedExt], Legend[G, Lbl]) =
    cjoin.count match {
      case 1 =>
        (Some(cjoin.toStream.head.data), joinLegend(cjoin))
      case _ =>
        val freshColumns: C.Join[G, C.Single[Lbl, Ext[Nothing, Nothing]]] =
          (cjoin traverse freshenSingle
           eval ((cjoin foldMap (_.data.header.keySet),
                  Stream from 0 map surrogateColName)))
        (joinTree(freshColumns map (_.data |> mem))
           map (joined => ExtMem(Optimizer optimize joined)),
         joinLegend(freshColumns))
    }

  /** Extract a relation to scan all of `table`, and a legend to
    * match.
    */
  def dynamicSchema[Lbl](table: C.Table[Lbl, ClosedExt]): (ClosedExt, Legend.U[Lbl]) = {
    val (oce, lg) = foldJoin(table.columns)
    (oce getOrElse ExtMem(EmptyRel(table typedColumnFoldMap
                                     {(c, p) => Vector((c, p))} toMap)),
     table.legend |+| lg)
  }
}
