package com.clarifi.reporting.writers

import collection.immutable.IndexedSeq
import com.clarifi.reporting._
import scalaz.{Monad, Monoid}
import scalaz.syntax.bifunctor._
import scalaz.syntax.monad._
import scalaz.syntax.traverse.{ToFunctorOps => _, ToFunctorOpsUnapply => _, _}
import scalaz.syntax.std.list._
import scalaz.std.option._
import scalaz.std.vector._
import scalaz.std.list._
import scalaz.std.tuple._

import Tabular.Label
import TreeTabular._

/** i.e. a Rose Tree */
case class TreeEntry[A](expanded: Boolean, level: Int, size: Int, value: A, loadChildren: () => ObservableTree[A]) {
  lazy val children: ObservableTree[A] = loadChildren()

  def foldTreeEntry[B](f: A => Vector[B] => B) : B = {
    f(value)(loadChildren() map (_.foldTreeEntry(f)))
  }

}

object TreeTabular {
  /** i.e. a forest of Rose Trees*/
  type ObservableTree[A] = Vector[TreeEntry[A]]

  def toRows[A](ot: ObservableTree[A]): Vector[TreeEntry[A]] =
    ot.flatMap (e => e +: (
      if (e.expanded)
        toRows(e.children)
      else Vector()))

  /** Keep the tree in the monad.  However, since we do that, we need to strictly load the entire tree -
    * there's no combinator >>=' :: (() -> m a) -> ( (() -> a) -> m b) -> m b
    * Useful for e.g. the ExcelWriter, where we traverse the whole tree to export it, anyways.  Don't use
    * in a lazier writer, like JavaFX, though.
    */
  def toObservableTree2[F[_], A](tt: TreeTabular[F, A], level: Int = 0)(implicit m: Monad[F]): F[ObservableTree[A]] = for {
    ch <- tt.children.slice(0, none) // :: indexedSeq[A]
    ot <- ch.toList.foldLeftM(Vector[TreeEntry[A]]())((t, a) => a match {
      case (v, ttt) => ttt.size >>= (sz =>
        toObservableTree2(ttt, level + 1)(m)
          >>= (children => m.pure(t :+ TreeEntry(true, level, sz, v, () => children))))
    })
  } yield ot

  def toObservableTree[F[_], A](tt: TreeTabular[F, A], level: Int = 0)(implicit m: Monad[F], r: Run[F]): ObservableTree[A] = r.run(for {
    ch <- tt.children.slice(0, none)
    ot <- ch.toList.foldLeftM(Vector[TreeEntry[A]]())((t, a) => a match {
      case (v, ttt) => ttt.size map (sz =>
        t :+ TreeEntry(false, level, sz, v, () =>
          toObservableTree(ttt, level + 1)(m, r)))
    })
  } yield ot)

  /** Strictly load entire tree, use faster traversal */
  def toObservableTree3[F[_], A](tt: TreeTabular[F, A], level: Int = 0)(implicit r: Run[F]): ObservableTree[A] = {
    def mkEntry(v: A, ttt: TreeTabular[F,A]): TreeEntry[A] = {
      val childNodes = toObservableTree3(ttt, level + 1)(r)
      TreeEntry(false, level, childNodes.size, v, () => childNodes)
    }
	
    val ch1: F[IndexedSeq[(A,TreeTabular[F,A])]] = tt.children.slice(0, none)	
    val ch2: IndexedSeq[(A,TreeTabular[F,A])] = r.run(ch1)
	
    var i = 0
    var result = Vector[TreeEntry[A]]()
    val n = ch2.size
    while (i < n) {
      val (v, ttt) = ch2(i)
      val te = mkEntry(v, ttt)

      result = result :+ te
      i = i + 1
    }
	
    result
  }

  /* A dummy tree tabular with no content, useful for debugging.
   * Likely implements some things in an unexpected way.
   */
  def dummy[F[_],A](implicit M: Monad[F]): TreeTabular[F, A] =
    new TreeTabular[F, A] {
      def F = M
      def children = Tabular.dummy[F,(A,TreeTabular[F,A])](M)
      def relation = {
        import relational._
        Closed(ExtRel(RelEmpty(Map()), ""),Map())
      }
    }

}


/** Tree tabular is essentially a forest of Rose Trees. */
abstract class TreeTabular[F[_], A] extends GenTabular[TreeTabular, F, A] { self =>
  implicit def F: Monad[F]

  def children: Tabular[F,(A,TreeTabular[F,A])]

  /** @see Tabular.columnIds */
  def columnIds = children.columnIds
  /** @see Tabular.columnLabels */
  def columnLabels = children.columnLabels

  def displayRules = children.displayRules

  /** Retrieve root-level rows [start,stop], or to end of the root-level rows
    * if no stop index is provided. */
  def slice(start: Int, stop: Option[Int]): F[IndexedSeq[A]] =
    children.slice(start, stop).map(_ map (_._1))

  /** Return the number of root-level rows. */
  def size: F[Int] = children.size

  /** Transform the values of this TreeTabular data. */
  def map[B](f: A => B): TreeTabular[F,B] = new TreeTabular[F,B] {
    implicit def F = self.F
    def relation = self.relation
    def children = self.children.map { case (a, t) => (f(a), t map f) }
  }

  /** A collection of a few useful catamorphisms */

  /** treeFold f (Tree b children) = f b (map (treeFold f) children)
    * scanr f = mconcat . map (treeFold f)
    */
  def scanr[B](f: A => Vector[B] => B)(implicit m: Monoid[B]) : F[B] =
    TreeTabular.toObservableTree2(self).map(_.map(_.foldTreeEntry(f))).map(_.suml)

  def scanr2[B](f: A => Vector[B] => B)(concat: Vector[B] => B) : F[B] =
    TreeTabular.toObservableTree2(self).map(_.map(_.foldTreeEntry(f))).map(vec => concat(vec))

  def scanr3[B](f: A => Vector[B] => B)(concat: Vector[B] => B)(implicit r: Run[F]) : B = {
    val vec = TreeTabular.toObservableTree3(self).map(_.foldTreeEntry(f))
    concat(vec)
  }

  def foldForest[B](f: Vector[A] => B)(g: (B, Vector[B]) => B): F[B] = {
    val grabVals: (TreeEntry[A] => (A, Vector[TreeEntry[A]])) =
        { case TreeEntry(_, _, _, value, loadChildren) => (value, loadChildren()) }
    def fold(vs: Vector[TreeEntry[A]]): B = {
      g tupled ( vs.map(grabVals)
                   .unzip
                   .bimap( f
                         , _.map(fold _)
                         )
               )
    }
    TreeTabular.toObservableTree2(self).map(x=>fold(x))
  }

  /** f takes the current "slice" and turns it into an F[B].
    * g combines the current slice with your children's slices, and returns the combined value.
    */
  def foldTree[B](f:Tabular[F,A] => F[B])(g:B => List[B] => B):F[B] = {
    val t: Tabular[F,(A,TreeTabular[F,A])] = self.children
    val curLevel:Tabular[F,A] = t.map(_._1)
    // Leaf nodes will have children with 0 rows.  Filter them out.
    val children:F[List[TreeTabular[F,A]]] = t.map(_._2)
                                              .takeAll
                                              .map( _.toList.filterM(_.size.map((x:Int) => x > 0) )(F))
                                              .join
    val dispCurLevel = f(curLevel)
    val visitChildren = children.map( _.map( _.foldTree(f)(g))
                                       .toList
                                       .sequence)
                                .join
    F.lift2(Function.uncurried(g)).apply(dispCurLevel, visitChildren)
    }

  /** Like fold tree, but pass around an extra parameter generated by your parent.
    * For example, when printing out a pie chart, the parameter could be your parent's name
    * and nextC generates a name from your parent.
    */
  def foldTreeWithParent[B,C](c:C)(nextC: A => C)(f: C => Tabular[F,A] => F[B])(g:B => List[B] => B):F[B] = {
    val t: Tabular[F,(A,TreeTabular[F,A])] = self.children
    val curLevel:Tabular[F,A] = t.map(_._1)
    // Leaf nodes will have children with 0 rows.  Filter them out.
    val children:F[List[(A, TreeTabular[F,A])]]
      = t.takeAll
         .map( _.toList.filterM(_._2.size.map((x:Int) => x > 0) )(F))
         .join
    val dispCurLevel = f(c)(curLevel)
    val visitChildren = children.map(_.map { case (parent, tab) =>
                                                tab.foldTreeWithParent( nextC(parent) )(nextC)(f)(g)
                                           }
                                      .toList
                                      .sequence
                                    ).join
    F.lift2(Function.uncurried(g)).apply(dispCurLevel, visitChildren)
    }


  private def transTabulars(f: Tabular[F,(A,TreeTabular[F,A])]
                            => Tabular[F,(A,TreeTabular[F,A])]): TreeTabular[F,A] =
    new TreeTabular[F,A] {
      implicit def F = self.F
      def relation = self.relation
      lazy val children = f(self.children.map {case (p1, p2) => p1 -> p2.transTabulars(f)})
    }

  def ordering = children.ordering

  /** Sort the rows in this Tabular by the given column. */
  def orderBy(o: IndexedSeq[(Label, SortOrder)]): TreeTabular[F,A] =
    transTabulars(_.orderBy(o))

  /** Clear any ordering applied to this Tabular. */
  def clearOrder: TreeTabular[F,A] = transTabulars(_.clearOrder)

  /** Answer self with columns relabeled. */
  def label(labels: Legend.U[Label]): TreeTabular[F,A] =
    transTabulars(_.label(labels))

  ///** Transform the underlying relation - this should not modify the type of this table. */
  //def apply(f: Relation[Header] => Relation[Header]): Tabular[F,A]
}
